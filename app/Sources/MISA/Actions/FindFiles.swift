import AppKit

/// "Find my resume pdf", "where is homework 6", "find photos from last week", "find the zip I downloaded yesterday".
///
/// Spotlight (`mdfind`) searches your home folder by name, narrowed by kind, date and folder when
/// you mention them. If no names match, it looks inside files instead. Results are numbered, so
/// "open 2" or "show 3 in Finder" works next, and a single result becomes "this" for any other
/// request ("move it to Desktop", "copy the text for AI").
enum FindFiles {
    struct Query {
        var words: [String] = []
        var kind: Kind?
        var dates: (from: String, to: String?)?
        var dateLabel: String?
        var folder: URL?
        var folderLabel: String?
    }

    enum Kind: String {
        case pdf, image, video, audio, document, slides, spreadsheet, folder, archive

        var types: [String] {
            switch self {
            case .pdf: return ["com.adobe.pdf"]
            case .image: return ["public.image"]
            case .video: return ["public.movie"]
            case .audio: return ["public.audio"]
            case .document: return ["org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc", "com.apple.iwork.pages.sffpages",
                                    "com.apple.iwork.pages.pages", "public.rtf", "com.microsoft.word.wordml", "org.oasis-open.opendocument.text"]
            case .slides: return ["org.openxmlformats.presentationml.presentation", "com.microsoft.powerpoint.ppt",
                                  "com.apple.iwork.keynote.sffkey", "com.apple.iwork.keynote.key"]
            case .spreadsheet: return ["org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls", "public.comma-separated-values-text",
                                       "com.apple.iwork.numbers.sffnumbers", "com.apple.iwork.numbers.numbers"]
            case .folder: return ["public.folder"]
            case .archive: return ["public.zip-archive", "public.archive"]
            }
        }
        var noun: String {
            switch self {
            case .pdf: return "PDFs"
            case .image: return "images"
            case .video: return "videos"
            case .audio: return "audio files"
            case .document: return "documents"
            case .slides: return "presentations"
            case .spreadsheet: return "spreadsheets"
            case .folder: return "folders"
            case .archive: return "archives"
            }
        }
    }

    private static let kindWords: [String: Kind] = [
        "pdf": .pdf, "pdfs": .pdf,
        "photo": .image, "photos": .image, "image": .image, "images": .image, "picture": .image, "pictures": .image,
        "pic": .image, "pics": .image, "png": .image, "jpg": .image, "jpeg": .image, "heic": .image,
        "video": .video, "videos": .video, "movie": .video, "movies": .video, "recording": .video, "recordings": .video, "mov": .video, "mp4": .video,
        "song": .audio, "songs": .audio, "audio": .audio, "music": .audio, "mp3": .audio, "voice memo": .audio,
        "doc": .document, "docs": .document, "document": .document, "documents": .document, "word doc": .document, "essay": .document, "docx": .document,
        "slides": .slides, "slideshow": .slides, "presentation": .slides, "presentations": .slides, "powerpoint": .slides, "keynote": .slides, "deck": .slides, "pptx": .slides,
        "spreadsheet": .spreadsheet, "spreadsheets": .spreadsheet, "excel": .spreadsheet, "sheet": .spreadsheet, "csv": .spreadsheet, "xlsx": .spreadsheet,
        "folder": .folder, "folders": .folder,
        "zip": .archive, "zips": .archive, "archive": .archive,
    ]

    /// Words that only glue the request together.
    private static let filler: Set<String> = [
        "my", "the", "a", "an", "file", "files", "called", "named", "titled", "me", "please", "that", "which", "i", "it", "is",
        "for", "of", "with", "some", "all", "any", "one", "thing", "stuff", "was", "had", "have", "where", "did", "put", "go", "went",
        "made", "saved", "wrote", "got", "from", "on", "in", "inside", "at", "to", "and", "or", "can", "you", "could", "help",
    ]

    private static let starts = ["find me ", "find my ", "find the ", "find ", "where is ", "where's ", "wheres ", "where are ", "where did i put ",
                                 "locate ", "look for ", "search my mac for ", "search my computer for ", "search my files for ", "search files for "]

    /// A find request, or nil. Searches of the web or YouTube are left to WebOpener.
    static func parse(_ raw: String) -> Query? {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!")))
        for lead in ["please ", "hey misa ", "misa ", "can you ", "could you ", "help me "] where s.hasPrefix(lead) { s = String(s.dropFirst(lead.count)) }
        if ["find", "find files", "find a file", "find something", "locate", "search my mac", "search my files"].contains(s) { return Query() }
        guard let start = starts.first(where: { s.hasPrefix($0) }) else { return nil }
        s = String(s.dropFirst(start.count))
        if [" on youtube", " on google", " online", " on the web", " on the internet"].contains(where: s.hasSuffix) { return nil }

        var q = Query()
        // Dates
        let dates: [(String, (String, String?), String)] = [
            ("yesterday", ("$time.today(-1)", "$time.today"), "yesterday"),
            ("today", ("$time.today", nil), "today"),
            ("last week", ("$time.this_week(-1)", "$time.this_week"), "last week"),
            ("this week", ("$time.this_week", nil), "this week"),
            ("last month", ("$time.this_month(-1)", "$time.this_month"), "last month"),
            ("this month", ("$time.this_month", nil), "this month"),
            ("this year", ("$time.this_year", nil), "this year"),
            ("recently", ("$time.today(-7)", nil), "the past week"),
            ("recent", ("$time.today(-7)", nil), "the past week"),
            ("lately", ("$time.today(-7)", nil), "the past week"),
            ("latest", ("$time.today(-7)", nil), "the past week"),
            ("newest", ("$time.today(-7)", nil), "the past week"),
        ]
        for (word, range, label) in dates where s.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
            q.dates = range
            q.dateLabel = label
            s = s.replacingOccurrences(of: "\\b\(word)\\b", with: " ", options: .regularExpression)
            break
        }
        // Folder: "in downloads", "on my desktop", "I downloaded"
        let folders: [(String, URL, String)] = [
            ("downloads", Paths.downloads, "Downloads"), ("downloaded", Paths.downloads, "Downloads"),
            ("desktop", Paths.desktop, "Desktop"), ("documents", Paths.home.appendingPathComponent("Documents"), "Documents"),
        ]
        for (word, url, label) in folders where s.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
            // "documents" is also a kind; only treat it as the folder after in/on/from.
            if word == "documents", s.range(of: "\\b(in|on|from) (my )?documents\\b", options: .regularExpression) == nil { continue }
            q.folder = url
            q.folderLabel = label
            s = s.replacingOccurrences(of: "\\b(in |on |from )?(my |the )?\(word)( folder)?\\b", with: " ", options: .regularExpression)
            break
        }
        // Kind (two-word phrases first)
        for word in kindWords.keys.sorted(by: { $0.count > $1.count }) where s.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
            q.kind = kindWords[word]
            s = s.replacingOccurrences(of: "\\b\(word)\\b", with: " ", options: .regularExpression)
            break
        }
        // A dotted extension in the name ("budget.xlsx") stays part of the name.
        q.words = s.split { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "-" && $0 != "_" && $0 != "'" }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".'")) }
            .filter { !$0.isEmpty && !filler.contains($0) }
        return q
    }

    // MARK: Searching

    private static func predicate(_ q: Query, content: Bool) -> String {
        var parts: [String] = []
        let field = content ? "kMDItemTextContent" : "kMDItemFSName"
        for w in q.words {
            let clean = w.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "*", with: "")
            if content {
                parts.append("kMDItemTextContent == \"\(clean)\"cdw") // whole words inside the file
            } else if clean.count > 3 {
                parts.append("\(field) == \"*\(clean)*\"cd")
            } else {
                // Short words ("ai", "cs", "hw") only as a whole word, or they match half the disk.
                let c = clean
                let forms = ["\(c) *", "* \(c) *", "* \(c).*", "\(c).*", "\(c)_*", "*_\(c)_*", "*_\(c).*", "\(c)-*", "*-\(c)-*", "*-\(c).*", "* \(c)_*", "* \(c)-*"]
                parts.append("(" + forms.map { "\(field) == \"\($0)\"cd" }.joined(separator: " || ") + ")")
            }
        }
        if let k = q.kind {
            parts.append("(" + k.types.map { "kMDItemContentTypeTree == \"\($0)\"" }.joined(separator: " || ") + ")")
        }
        if let d = q.dates {
            parts.append("kMDItemFSContentChangeDate >= \(d.from)")
            if let to = d.to { parts.append("kMDItemFSContentChangeDate < \(to)") }
        }
        return parts.joined(separator: " && ")
    }

    /// Paths nobody means: app internals, caches, code dependencies, photo library guts.
    private static func wanted(_ u: URL) -> Bool {
        let p = u.path
        let lib = Paths.home.appendingPathComponent("Library").path + "/"
        if p.hasPrefix(lib) { return false }
        for part in u.pathComponents.dropLast() {
            if part.hasPrefix(".") || part == "node_modules" || part.hasSuffix(".app") || part.hasSuffix(".photoslibrary")
                || part.hasSuffix(".xcodeproj") || part == "DerivedData" || part == "build" || part == "dist" { return false }
        }
        return !u.lastPathComponent.hasPrefix(".")
    }

    private static func search(_ q: Query, content: Bool) -> [URL] {
        let pred = predicate(q, content: content)
        guard !pred.isEmpty else { return [] }
        let root = q.folder ?? Paths.home
        let out = FileOps.run("/usr/bin/mdfind", ["-onlyin", root.path, pred]).out
        return out.split(separator: "\n").prefix(800).map { URL(fileURLWithPath: String($0)) }.filter(wanted)
    }

    /// Best first: whole-word name matches, then the most recently changed.
    private static func rank(_ hits: [URL], _ q: Query) -> [URL] {
        let words = q.words.map { $0.lowercased() }
        func score(_ u: URL) -> Int {
            let name = u.deletingPathExtension().lastPathComponent.lowercased()
            let tokens = Set(name.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            var s = 0
            if !words.isEmpty, name == words.joined(separator: " ") { s += 50 }
            s += words.filter(tokens.contains).count * 10
            if name.hasPrefix(words.first ?? "\u{0}") { s += 5 }
            return s
        }
        let scored = hits.map { ($0, score($0), FileOps.modified($0)) }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }.map(\.0)
    }

    // MARK: Replies

    static let shown = 6

    static func run(_ q: Query) -> Reply {
        guard !q.words.isEmpty || q.kind != nil || q.dates != nil else {
            return Reply(text: "What should I look for? Try “find my resume pdf” or “find photos from last week”.")
        }
        var hits = search(q, content: false)
        var inside = false
        if hits.isEmpty, !q.words.isEmpty {
            hits = search(q, content: true)
            inside = !hits.isEmpty
        }
        let what = describe(q)
        FileOps.log("find: \(what) → \(hits.count) hit(s)\(inside ? " (by content)" : "")")
        guard !hits.isEmpty else {
            var tips: [Reply.Suggestion] = []
            if q.dates != nil || q.kind != nil || q.folder != nil, !q.words.isEmpty {
                tips.append(.init(label: "Search everywhere", prompt: "find \(q.words.joined(separator: " "))"))
            }
            return Reply(text: "I couldn't find \(what) on your Mac.", suggestions: tips)
        }
        let ranked = rank(hits, q)
        let top = Array(ranked.prefix(shown))
        let more = ranked.count > shown ? " (showing the best \(shown) of \(ranked.count))" : ""
        let lead = inside ? "Nothing is named that, but these files mention it" : "Found \(ranked.count) \(ranked.count == 1 ? "match" : "matches")"

        if top.count == 1 { return single(top[0], lead: inside ? "This file mentions it" : "Found it") }

        let lines = top.enumerated().map { i, u in "\(i + 1). \(u.lastPathComponent)\n    \(where_(u)) · \(when(u))" }
        return Reply(
            text: "\(lead)\(more):\n\(lines.joined(separator: "\n"))\n\nSay “open \(top.count)”, “show 1 in Finder”, or “use 2” to work with one.",
            suggestions: [.init(label: "Open 1", prompt: "open 1"), .init(label: "Show 1 in Finder", prompt: "show 1 in Finder"),
                          .init(label: "Use 1", prompt: "use 1")],
            found: top
        )
    }

    /// One file, ready for "open it", "show in Finder", "move it to …".
    static func single(_ u: URL, lead: String = "Here it is") -> Reply {
        var s: [Reply.Suggestion] = [.init(label: "Open it", prompt: "open it"), .showInFinder]
        let k = FileOps.kind(u)
        if k != .folder { s.append(.init(label: "Move to Desktop", prompt: "move it to Desktop")) }
        if [.pdf, .document, .text, .folder].contains(k) { s.append(.init(label: "Copy text for AI", prompt: "copy the text for ai")) }
        if k == .image { s.append(.init(label: "Convert to JPG", prompt: "convert to jpg")) }
        return Reply(text: "\(lead): \(u.lastPathComponent)\n\(where_(u)) · \(when(u))", suggestions: s, outputs: [u], replacesFiles: [u])
    }

    /// "open 2", "show the second one in finder", "use 3", "the first one". Nil if it isn't that.
    static func pick(_ t: String, from found: [URL]) -> Reply? {
        guard !found.isEmpty else { return nil }
        let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5, "6th": 6]
        let re = try! NSRegularExpression(pattern: #"^(open|show|reveal|use|pick|select|choose|take|grab)?\s*(me\s+)?(the\s+)?(number\s+|no\.?\s*|#)?(\d|first|second|third|fourth|fifth|sixth|last|1st|2nd|3rd|4th|5th|6th)(\s+one)?(\s+file)?(\s+in\s+finder)?$"#)
        let ns = t as NSString
        guard let m = re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let verb = m.range(at: 1).location == NSNotFound ? "use" : ns.substring(with: m.range(at: 1))
        let which = ns.substring(with: m.range(at: 5))
        let n = which == "last" ? found.count : (Int(which) ?? ordinals[which] ?? 0)
        guard n >= 1, n <= found.count else { return Reply(text: "Pick a number from 1 to \(found.count).") }
        let u = found[n - 1]
        let finder = m.range(at: 8).location != NSNotFound || verb == "show" || verb == "reveal"
        if finder {
            FileOps.onMain { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            var r = single(u, lead: "Showing in Finder")
            r.suggestions.removeAll { $0.prompt == Reply.Suggestion.showInFinder.prompt }
            return r
        }
        if verb == "open" { return open(u) }
        return single(u, lead: "Got it")
    }

    static func open(_ u: URL) -> Reply {
        let ok = FileOps.onMain { NSWorkspace.shared.open(u) }
        FileOps.log("find: opened \(MoveFiles.tilde(u))")
        var r = single(u, lead: ok ? "Opening" : "I couldn't open")
        r.suggestions.removeAll { $0.prompt == "open it" }
        return r
    }

    private static func describe(_ q: Query) -> String {
        var s = q.words.isEmpty ? (q.kind?.noun ?? "files") : "“\(q.words.joined(separator: " "))”"
        if !q.words.isEmpty, let k = q.kind { s += " (\(k.noun))" }
        if let f = q.folderLabel { s += " in \(f)" }
        if let d = q.dateLabel { s += " from \(d)" }
        return s
    }

    private static func where_(_ u: URL) -> String { MoveFiles.tilde(u.deletingLastPathComponent()) }

    private static func when(_ u: URL) -> String {
        let d = FileOps.modified(u)
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = Calendar.current.isDateInToday(d) || Calendar.current.isDateInYesterday(d) ? .short : .none
        return "edited " + f.string(from: d)
    }
}
