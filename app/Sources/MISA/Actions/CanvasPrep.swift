import AppKit
import PDFKit

/// Gets a file ready to submit: turns it into a PDF named like "Than_Homework_6_2026-11-19.pdf".
enum CanvasPrep {
    static func run(_ files: [URL]) -> Reply {
        var outputs: [URL] = [], skipped: [String] = []
        for f in files {
            guard let out = makePDF(from: f) else { skipped.append(f.lastPathComponent); continue }
            outputs.append(out)
        }
        guard !outputs.isEmpty else {
            return Reply(text: "I couldn't turn those into PDFs. I can do PDFs, images, Word, RTF, text and web pages.")
        }
        FileOps.log("canvas-prep: \(outputs.map(\.lastPathComponent).joined(separator: ", "))")
        var text = "Ready to submit:\n" + FileOps.bullets(outputs.map(\.lastPathComponent))
        if files.contains(where: { FileOps.kind($0) == .document }) {
            text += "\n\nWord files are converted with basic formatting. Open the PDF and check it before you submit."
        }
        if !skipped.isEmpty { text += "\n\nSkipped: " + skipped.joined(separator: ", ") }
        return Reply(text: text, suggestions: [.showInFinder], outputs: outputs)
    }

    /// "Homework 6 – Bug Report (final).docx" → "Than_Homework_6_Bug_Report_final_2026-11-19.pdf"
    static func submissionName(for url: URL) -> String {
        let last = NSFullUserName().split(separator: " ").last.map(String.init) ?? NSUserName()
        let words = url.deletingPathExtension().lastPathComponent
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.lowercased() != last.lowercased() }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return ([last] + words + [f.string(from: Date())]).joined(separator: "_") + ".pdf"
    }

    private static func makePDF(from src: URL) -> URL? {
        let out = FileOps.uniqueURL(in: src.deletingLastPathComponent(), name: submissionName(for: src))
        switch FileOps.kind(src) {
        case .pdf:
            return (try? FileManager.default.copyItem(at: src, to: out)) != nil ? out : nil
        case .image:
            guard let image = NSImage(contentsOf: src), let page = PDFPage(image: image) else { return nil }
            let doc = PDFDocument()
            doc.insert(page, at: 0)
            return doc.write(to: out) ? out : nil
        case .document, .text:
            guard let text = try? NSAttributedString(url: src, options: [:], documentAttributes: nil) else { return nil }
            return FileOps.onMain { printToPDF(text, to: out) } ? out : nil
        default:
            return nil
        }
    }

    /// Lays text out on US Letter pages with 1-inch margins and saves it as a PDF.
    private static func printToPDF(_ text: NSAttributedString, to url: URL) -> Bool {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.topMargin = 72; info.bottomMargin = 72; info.leftMargin = 72; info.rightMargin = 72
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 612 - 144, height: 792 - 144))
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.sizeToFit()

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        return op.run() && FileManager.default.fileExists(atPath: url.path)
    }
}
