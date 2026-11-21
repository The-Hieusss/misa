import AppKit
import WebKit

/// The web view, plus file drag-and-drop. Swift keeps the file paths; the web side only sees names.
///
/// Finder drags carry file URLs. Apps like Photos instead carry *file promises*: the real file
/// (the original video or photo) only exists once the receiver picks a folder and asks for it,
/// and the drag also includes a preview image as a plain file. So promises win when present;
/// otherwise a Photos video would arrive as its JPG preview.
final class DropWebView: WKWebView {
    var onDrop: (([URL]) -> Void)?
    var onHover: ((Bool) -> Void)?

    /// Where promised files (e.g. from Photos) are written.
    static let promiseFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/From Photos", isDirectory: true)

    private let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [.fileURL])
    }

    private func promises(_ info: NSDraggingInfo) -> [NSFilePromiseReceiver] {
        info.draggingPasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func hasFiles(_ info: NSDraggingInfo) -> Bool {
        !promises(info).isEmpty || !fileURLs(info).isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else { return super.draggingEntered(sender) }
        onHover?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasFiles(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasFiles(sender) ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let types = (pb.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
        let receivers = promises(sender)
        let urls = fileURLs(sender)
        FileOps.log("drop: \(receivers.count) promise(s), \(urls.count) file(s) [\(urls.map(\.lastPathComponent).joined(separator: ", "))] types=\(Set(types).sorted().joined(separator: ","))")

        if !receivers.isEmpty {
            onHover?(false)
            receive(receivers)
            return true
        }
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onHover?(false)
        onDrop?(urls)
        return true
    }

    /// Asks the source app to write each promised file, then hands all of them over at once.
    private func receive(_ receivers: [NSFilePromiseReceiver]) {
        let dest = Self.promiseFolder
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let group = DispatchGroup()
        let lock = NSLock()
        var got: [URL] = []
        for r in receivers {
            // One receiver can promise several files; the reader is called once per file.
            var remaining = max(1, r.fileNames.count)
            for _ in 0..<remaining { group.enter() }
            r.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: promiseQueue) { url, error in
                lock.lock()
                if let error { FileOps.log("drop: promise failed: \(error.localizedDescription)") } else { got.append(url) }
                let leave = remaining > 0
                if leave { remaining -= 1 }
                lock.unlock()
                if leave { group.leave() }
            }
        }
        // Videos stored in iCloud download first, so allow a while before giving up on stragglers.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = group.wait(timeout: .now() + 600)
            lock.lock(); let files = got.sorted { $0.lastPathComponent < $1.lastPathComponent }; lock.unlock()
            DispatchQueue.main.async {
                FileOps.log("drop: received \(files.map(\.lastPathComponent).joined(separator: ", ")) in \(dest.path)")
                if !files.isEmpty { self?.onDrop?(files) }
            }
        }
    }
}
