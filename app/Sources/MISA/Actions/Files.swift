import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

/// Well-known folders.
enum Paths {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }
    static var disposable: URL { home.appendingPathComponent("Disposable") }
    static var screenshots: URL { home.appendingPathComponent("Screenshots") }
    static var downloads: URL { fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }
    static var desktop: URL { fm.urls(for: .desktopDirectory, in: .userDomainMask)[0] }
    static var disposableLog: URL { home.appendingPathComponent("Library/Logs/disposable.log") }
    static var misaLog: URL { home.appendingPathComponent("Library/Logs/misa.log") }
}

enum FileKind { case image, video, pdf, document, text, folder, other }

/// Small, reusable file helpers. Nothing here deletes permanently: removal always goes to the Trash.
enum FileOps {
    static let fm = FileManager.default

    static func kind(_ url: URL) -> FileKind {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Packages like .rtfd are folders on disk but documents to people.
            if url.pathExtension.lowercased() == "rtfd" { return .document }
            return .folder
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        let docs = ["docx", "doc", "rtf", "odt", "html", "htm", "webarchive", "pages"]
        if docs.contains(url.pathExtension.lowercased()) { return .document }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .json) { return .text }
        return .other
    }

    /// "report.pdf" → "report 1.pdf" → "report 2.pdf" … until the name is free.
    static func uniqueURL(in dir: URL, name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 1
        while fm.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// Moves without ever overwriting. Returns where it ended up.
    @discardableResult
    static func move(_ src: URL, into dir: URL) throws -> URL {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueURL(in: dir, name: src.lastPathComponent)
        try fm.moveItem(at: src, to: dest)
        return dest
    }

    /// Copies without ever overwriting. Returns where the copy landed.
    @discardableResult
    static func copy(_ src: URL, into dir: URL) throws -> URL {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueURL(in: dir, name: src.lastPathComponent)
        try fm.copyItem(at: src, to: dest)
        return dest
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func trash(_ url: URL) throws {
        try fm.trashItem(at: url, resultingItemURL: nil)
    }

    /// Lists a folder's top level, skipping hidden files.
    static func contents(of dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    static func run(_ exe: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    /// Size on disk of a file or a whole folder.
    static func size(_ url: URL) -> Int64 {
        if kind(url) != .folder {
            return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        let r = run("/usr/bin/du", ["-sk", url.path])
        return (Int64(r.out.split(separator: "\t").first ?? "0") ?? 0) * 1024
    }

    static func human(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Inode change time: when a file arrived in its folder (what Disposable's timer uses).
    static func arrived(_ url: URL) -> Date {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return Date() }
        return Date(timeIntervalSince1970: TimeInterval(st.st_ctimespec.tv_sec))
    }

    static func created(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? arrived(url)
    }

    /// When the file was added to its folder (Finder's "Date Added").
    static func added(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate) ?? created(url)
    }

    static func isScreenshot(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ") || name.hasPrefix("Screen Recording ") {
            return true
        }
        guard let item = MDItemCreateWithURL(nil, url as CFURL),
              let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool else { return false }
        return flag
    }

    /// "• a\n• b\n…and 3 more"
    static func bullets(_ lines: [String], max: Int = 6) -> String {
        var out = lines.prefix(max).map { "• \($0)" }
        if lines.count > max { out.append("…and \(lines.count - max) more") }
        return out.joined(separator: "\n")
    }

    static func plural(_ n: Int, _ word: String) -> String {
        "\(n) \(word)\(n == 1 ? "" : "s")"
    }

    static func log(_ line: String, to file: URL = Paths.misaLog) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime])
        let data = Data("\(stamp) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file)
        }
    }

    /// Runs `work` on the main thread and waits for it (AppKit printing and the pasteboard need main).
    static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
