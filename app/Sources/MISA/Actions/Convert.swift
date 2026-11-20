import AppKit
import PDFKit

/// Converting files with tools built into macOS. New files go next to the originals; originals are untouched.
enum Convert {
    static func toJPG(_ files: [URL]) -> Reply {
        let images = files.filter { FileOps.kind($0) == .image }
        guard !images.isEmpty else { return Reply(text: "None of those are images.") }
        var outputs: [URL] = [], skipped: [String] = []
        for img in images {
            if ["jpg", "jpeg"].contains(img.pathExtension.lowercased()) { skipped.append(img.lastPathComponent); continue }
            let out = FileOps.uniqueURL(in: img.deletingLastPathComponent(),
                                        name: img.deletingPathExtension().lastPathComponent + ".jpg")
            let r = FileOps.run("/usr/bin/sips", ["-s", "format", "jpeg", "-s", "formatOptions", "85", img.path, "--out", out.path])
            if r.status == 0 { outputs.append(out) } else { skipped.append(img.lastPathComponent) }
        }
        return finished("Converted \(FileOps.plural(outputs.count, "image")) to JPG", outputs, skipped: skipped)
    }

    /// Longest side 1600 px: small enough for uploads and chats, still sharp.
    static func shrink(_ files: [URL], maxSide: Int = 1600) -> Reply {
        let images = files.filter { FileOps.kind($0) == .image }
        guard !images.isEmpty else { return Reply(text: "None of those are images.") }
        var outputs: [URL] = [], skipped: [String] = []
        for img in images {
            let base = img.deletingPathExtension().lastPathComponent
            let out = FileOps.uniqueURL(in: img.deletingLastPathComponent(), name: "\(base) small.jpg")
            let r = FileOps.run("/usr/bin/sips", ["-Z", "\(maxSide)", "-s", "format", "jpeg", "-s", "formatOptions", "80", img.path, "--out", out.path])
            if r.status == 0 { outputs.append(out) } else { skipped.append(img.lastPathComponent) }
        }
        let before = images.reduce(Int64(0)) { $0 + FileOps.size($1) }
        let after = outputs.reduce(Int64(0)) { $0 + FileOps.size($1) }
        return finished("Shrank \(FileOps.plural(outputs.count, "image")) (\(FileOps.human(before)) → \(FileOps.human(after)))", outputs, skipped: skipped)
    }

    /// Combines images (in name order) into one PDF.
    static func imagesToPDF(_ files: [URL]) -> Reply {
        let images = files.filter { FileOps.kind($0) == .image }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !images.isEmpty else { return Reply(text: "None of those are images.") }
        let pdf = PDFDocument()
        for img in images {
            if let image = NSImage(contentsOf: img), let page = PDFPage(image: image) {
                pdf.insert(page, at: pdf.pageCount)
            }
        }
        guard pdf.pageCount > 0 else { return Reply(text: "I couldn't read those images.") }
        let name = images.count == 1 ? images[0].deletingPathExtension().lastPathComponent + ".pdf" : "Combined.pdf"
        let out = FileOps.uniqueURL(in: images[0].deletingLastPathComponent(), name: name)
        guard pdf.write(to: out) else { return Reply(text: "Couldn't save the PDF.") }
        return finished("Made a \(pdf.pageCount)-page PDF", [out])
    }

    /// Screen recordings and iPhone videos (.mov) → .mp4, which uploads and plays everywhere.
    static func toMP4(_ files: [URL]) -> Reply {
        let videos = files.filter { FileOps.kind($0) == .video && $0.pathExtension.lowercased() != "mp4" }
        guard !videos.isEmpty else { return Reply(text: "I didn't find any videos to convert (they may already be .mp4).") }
        var outputs: [URL] = [], skipped: [String] = []
        for v in videos {
            let out = FileOps.uniqueURL(in: v.deletingLastPathComponent(), name: v.deletingPathExtension().lastPathComponent + ".mp4")
            let r = FileOps.run("/usr/bin/avconvert", ["--source", v.path, "--output", out.path, "--preset", "PresetHighestQuality"])
            if r.status == 0, FileManager.default.fileExists(atPath: out.path) { outputs.append(out) } else { skipped.append(v.lastPathComponent) }
        }
        return finished("Converted \(FileOps.plural(outputs.count, "video")) to MP4", outputs, skipped: skipped)
    }

    private static func finished(_ headline: String, _ outputs: [URL], skipped: [String] = []) -> Reply {
        var text = outputs.isEmpty ? "Nothing to convert." : "\(headline):\n" + FileOps.bullets(outputs.map(\.lastPathComponent))
        if !skipped.isEmpty { text += "\n\nSkipped: " + skipped.joined(separator: ", ") }
        if !outputs.isEmpty { FileOps.log("convert: \(headline)") }
        return Reply(text: text, suggestions: outputs.isEmpty ? [] : [.showInFinder], outputs: outputs)
    }
}
