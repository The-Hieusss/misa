import AppKit
import PDFKit

/// Pulls the text out of files (or a whole code folder) and puts it on the clipboard,
/// ready to paste into any AI chat. Nothing is uploaded anywhere.
enum CopyForAI {
    static let maxTotal = 200_000 // characters
    static let maxPerFile = 40_000
    private static let skipDirs: Set<String> = [
        "node_modules", ".git", ".build", "build", "dist", ".next", ".venv", "venv", "__pycache__", "Pods", "DerivedData", ".idea", ".vscode",
    ]

    static func run(_ files: [URL]) -> Reply {
        var parts: [String] = [], used: [String] = [], skipped: [String] = []
        var total = 0

        for f in files {
            if FileOps.kind(f) == .folder {
                let (text, count) = folderText(f, budget: maxTotal - total)
                parts.append(text)
                total += text.count
                used.append("\(f.lastPathComponent)/ (\(FileOps.plural(count, "file")))")
            } else if let text = extract(f) {
                let clipped = clip(text, maxPerFile)
                parts.append("===== \(f.lastPathComponent) =====\n\(clipped)")
                total += clipped.count
                used.append(f.lastPathComponent)
            } else {
                skipped.append(f.lastPathComponent)
            }
            if total >= maxTotal { break }
        }

        guard !parts.isEmpty else {
            return Reply(text: "I couldn't get text out of those. I can read PDFs, Word, RTF, web pages, text and code files, and folders of code.")
        }
        let all = clip(parts.joined(separator: "\n\n"), maxTotal)
        FileOps.onMain {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(all, forType: .string)
        }
        FileOps.log("copy-for-ai: \(all.count) chars from \(used.count) item(s)")

        var text = "Copied \(all.count.formatted()) characters to the clipboard. Paste it into any AI chat.\n" + FileOps.bullets(used)
        if total >= maxTotal { text += "\n\nIt was long, so I stopped at \(maxTotal.formatted()) characters." }
        if !skipped.isEmpty { text += "\n\nCouldn't read: " + skipped.joined(separator: ", ") }
        return Reply(text: text)
    }

    static func extract(_ url: URL) -> String? {
        switch FileOps.kind(url) {
        case .pdf:
            return PDFDocument(url: url)?.string.flatMap { $0.isEmpty ? nil : $0 }
        case .document:
            let r = FileOps.run("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path])
            return r.status == 0 && !r.out.isEmpty ? r.out : nil
        case .text:
            return try? String(contentsOf: url, encoding: .utf8)
        default:
            // Unknown extension: accept it if it decodes as UTF-8 text (e.g. Makefile, .env.example).
            guard FileOps.size(url) < 1_000_000, let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return s
        }
    }

    /// A file tree plus the contents of each readable file, skipping build output and dependencies.
    private static func folderText(_ root: URL, budget: Int) -> (String, Int) {
        var tree: [String] = [], bodies: [String] = []
        var used = 0, count = 0
        let rootPath = root.standardizedFileURL.path
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return ("", 0)
        }
        for case let url as URL in e {
            let rel = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            let depth = rel.split(separator: "/").count - 1
            if FileOps.kind(url) == .folder {
                if skipDirs.contains(url.lastPathComponent) { e.skipDescendants(); continue }
                tree.append(String(repeating: "  ", count: depth) + url.lastPathComponent + "/")
                continue
            }
            tree.append(String(repeating: "  ", count: depth) + url.lastPathComponent)
            guard used < budget, FileOps.size(url) < 300_000, let text = extract(url), !text.isEmpty else { continue }
            let clipped = clip(text, min(maxPerFile, budget - used))
            bodies.append("===== \(rel) =====\n\(clipped)")
            used += clipped.count
            count += 1
        }
        let header = "===== \(root.lastPathComponent)/ (file tree) =====\n" + tree.joined(separator: "\n")
        return (([header] + bodies).joined(separator: "\n\n"), count)
    }

    private static func clip(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(max(0, n))) + "\n…[cut off]"
    }
}
