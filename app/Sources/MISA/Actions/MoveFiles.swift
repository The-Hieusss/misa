import Foundation

/// "Move this to Desktop", "copy these to Documents", "move Homework 6.pdf to Downloads",
/// "put it in CHM 101", and "undo" to put things back. Always confirms first, never overwrites.
enum MoveFiles {
    enum Op { case move, copy, trash }
    struct Request { let op: Op; let source: String; let dest: String }

    /// What the last move or copy did, so "undo" can reverse it. Only touched on Brain's action queue.
    private static var last: (op: Op, moves: [(now: URL, was: URL)])?

    private static let pattern = try! NSRegularExpression(
        pattern: #"^(?:please\s+|can you\s+|could you\s+)?(move|put|copy|send|drop)\s+(.+?)\s+(?:over to|onto|into|to|in|inside)\s+(?:the\s+|my\s+)?(.+?)(?:\s+folder)?[\s.!?]*$"#,
        options: [.caseInsensitive])

    static func parse(_ raw: String) -> Request? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = s as NSString
        guard let m = pattern.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let verb = ns.substring(with: m.range(at: 1)).lowercased()
        let quotes = CharacterSet(charactersIn: "\"'“”‘’")
        let source = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: quotes.union(.whitespaces))
        let dest = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: quotes.union(.whitespaces))
        guard !source.isEmpty, !dest.isEmpty else { return nil }
        return Request(op: verb == "copy" ? .copy : .move, source: source, dest: dest)
    }

    private static let pronouns: Set<String> = [
        "this", "these", "it", "them", "that", "those", "this file", "these files", "the file", "the files", "that file",
        "those files", "them all", "all of them", "everything", "this folder", "these folders", "the folder",
    ]
    static func meansDropped(_ source: String) -> Bool { pronouns.contains(source.lowercased()) }

    // MARK: Finding things

    private static var named: [String: URL] {
        let fm = FileManager.default, h = Paths.home
        func dir(_ d: FileManager.SearchPathDirectory, _ fallback: String) -> URL {
            fm.urls(for: d, in: .userDomainMask).first ?? h.appendingPathComponent(fallback)
        }
        return [
            "desktop": Paths.desktop, "downloads": Paths.downloads, "documents": dir(.documentDirectory, "Documents"),
            "docs": dir(.documentDirectory, "Documents"), "pictures": dir(.picturesDirectory, "Pictures"),
            "movies": dir(.moviesDirectory, "Movies"), "videos": dir(.moviesDirectory, "Movies"), "music": dir(.musicDirectory, "Music"),
            "home": h, "home folder": h, "screenshots": Paths.screenshots,
        ]
    }

    private static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    static func tilde(_ url: URL) -> String {
        let p = url.path, h = Paths.home.path
        return p.hasPrefix(h) ? "~" + p.dropFirst(h.count) : p
    }

    /// Spotlight search in your home folder, skipping Library, the Trash and hidden folders.
    private static func spotlight(_ query: String, folders: Bool) -> [URL] {
        let q = query.replacingOccurrences(of: "\"", with: "")
        let args = folders
            ? ["-onlyin", Paths.home.path, "kMDItemContentType == 'public.folder' && kMDItemFSName == \"\(q)\"c"]
            : ["-onlyin", Paths.home.path, "-name", q]
        let lib = Paths.home.appendingPathComponent("Library").path + "/"
        return FileOps.run("/usr/bin/mdfind", args).out.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            .filter { u in
                !u.path.hasPrefix(lib) && !u.pathComponents.contains { $0.hasPrefix(".") }
                    && FileManager.default.fileExists(atPath: u.path)
            }
    }

    private static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    enum Found<T> { case one(T), many([URL]), none }

    static let trashWords: Set<String> = ["trash", "the trash", "bin", "trash can", "recycle bin"]

    static func destination(_ text: String) -> Found<URL> {
        let t = text.lowercased()
        if t == "disposable" { return .one(Paths.disposable) }
        if let u = named[t] { return .one(u) }
        if text.hasPrefix("~") || text.hasPrefix("/") {
            let u = expand(text)
            return isDir(u) ? .one(u) : .none
        }
        let hits = spotlight(text, folders: true).sorted { $0.pathComponents.count < $1.pathComponents.count }
        switch hits.count {
        case 0: return .none
        case 1: return .one(hits[0])
        default: return .many(Array(hits.prefix(5)))
        }
    }

    static func source(_ text: String) -> Found<URL> {
        if text.hasPrefix("~") || text.hasPrefix("/") {
            let u = expand(text)
            return FileManager.default.fileExists(atPath: u.path) ? .one(u) : .none
        }
        let hits = spotlight(text, folders: false)
        let lower = text.lowercased()
        let exact = hits.filter {
            $0.lastPathComponent.lowercased() == lower || $0.deletingPathExtension().lastPathComponent.lowercased() == lower
        }
        if exact.count == 1 { return .one(exact[0]) }
        let pool = exact.isEmpty ? hits : exact
        switch pool.count {
        case 0: return .none
        case 1: return .one(pool[0])
        default:
            // Newest first: usually the one you mean.
            let newest = pool.sorted { FileOps.modified($0) > FileOps.modified($1) }
            return .many(Array(newest.prefix(5)))
        }
    }

    // MARK: The action

    /// `dropped` are the files last dropped on her (used for "this" / "these").
    static func run(_ req: Request, dropped: [URL]) -> Reply {
        let verb = req.op == .copy ? "copy" : "move" // (.trash is only set by trash())
        let Verb = verb.capitalized

        // Which files
        let files: [URL]
        if meansDropped(req.source) {
            guard !dropped.isEmpty else { return Reply(text: "Drop the files on me first, or tell me the file's name.") }
            files = dropped.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !files.isEmpty else { return Reply(text: "Those files aren't where they were anymore.") }
        } else {
            switch source(req.source) {
            case .one(let u): files = [u]
            case .none: return Reply(text: "I couldn't find a file called “\(req.source)” in your home folder.")
            case .many(let list):
                return Reply(text: "I found a few files like “\(req.source)”. Which one?",
                             suggestions: list.map { .init(label: tilde($0), prompt: "\(verb) \(tilde($0)) to \(req.dest)") })
            }
        }

        if trashWords.contains(req.dest.lowercased()) && req.op != .copy { return trash(files) }

        // Where to
        let dest: URL
        switch destination(req.dest) {
        case .one(let u): dest = u
        case .none: return Reply(text: "I couldn't find a folder called “\(req.dest)”. You can also give me a path, like ~/Documents/School.")
        case .many(let list):
            let src = meansDropped(req.source) ? req.source : tilde(files[0])
            return Reply(text: "There's more than one “\(req.dest)” folder. Which one?",
                         suggestions: list.map { .init(label: tilde($0), prompt: "\(verb) \(src) to \(tilde($0))") })
        }

        // Skip files already there, and folders into themselves.
        let todo = files.filter { f in
            f.deletingLastPathComponent().standardizedFileURL != dest.standardizedFileURL
                && !(dest.standardizedFileURL.path + "/").hasPrefix(f.standardizedFileURL.path + "/")
        }
        guard !todo.isEmpty else {
            return Reply(text: files.count == 1 ? "\(files[0].lastPathComponent) is already in \(tilde(dest))." : "Those are already in \(tilde(dest)).")
        }

        let what = todo.count == 1 ? todo[0].lastPathComponent : FileOps.plural(todo.count, "item")
        return Reply(
            text: "\(Verb) \(what) to \(tilde(dest))?",
            confirm: .init(
                title: "\(Verb) to \(tilde(dest))",
                items: todo.map { tilde($0.deletingLastPathComponent()) + "/" + $0.lastPathComponent },
                button: "\(Verb) \(todo.count)",
                danger: false
            ) {
                var done: [(now: URL, was: URL)] = [], failed = 0
                for f in todo {
                    do {
                        let now = req.op == .copy ? try FileOps.copy(f, into: dest) : try FileOps.move(f, into: dest)
                        done.append((now, f))
                    } catch {
                        failed += 1
                        FileOps.log("\(verb): \(f.lastPathComponent) failed: \(error.localizedDescription)")
                    }
                }
                guard !done.isEmpty else { return Reply(text: "I couldn't \(verb) \(todo.count == 1 ? "it" : "them"). It may be in use, or a folder I'm not allowed into.") }
                last = (req.op, done)
                FileOps.log("\(verb): \(done.count) item(s) to \(tilde(dest))")
                let renamed = done.contains { $0.now.lastPathComponent != $0.was.lastPathComponent }
                var text = "\(req.op == .copy ? "Copied" : "Moved") \(done.count == 1 ? done[0].now.lastPathComponent : FileOps.plural(done.count, "item")) to \(tilde(dest))."
                if renamed { text += " Something there had the same name, so I added a number." }
                if failed > 0 { text += " \(FileOps.plural(failed, "item")) couldn't be \(req.op == .copy ? "copied" : "moved")." }
                var r = Reply(text: text, suggestions: [.showInFinder, .init(label: "Undo", prompt: "Undo")], outputs: done.map(\.now))
                if req.op == .move { r.replacesFiles = done.map(\.now) }
                return r
            }
        )
    }

    /// "Move this to the Trash": recoverable, and "undo" brings it back.
    private static func trash(_ files: [URL]) -> Reply {
        let what = files.count == 1 ? files[0].lastPathComponent : FileOps.plural(files.count, "item")
        return Reply(
            text: "Move \(what) to the Trash?",
            confirm: .init(title: "Move to the Trash", items: files.map(tilde), button: "Trash \(files.count)", danger: true) {
                var done: [(now: URL, was: URL)] = []
                for f in files {
                    var landed: NSURL?
                    if (try? FileManager.default.trashItem(at: f, resultingItemURL: &landed)) != nil, let now = landed as URL? {
                        done.append((now, f))
                    }
                }
                guard !done.isEmpty else { return Reply(text: "I couldn't move \(files.count == 1 ? "it" : "them") to the Trash.") }
                last = (.trash, done)
                FileOps.log("trash-files: \(done.count) item(s)")
                return Reply(text: "Moved \(done.count == 1 ? done[0].was.lastPathComponent : FileOps.plural(done.count, "item")) to the Trash.",
                             suggestions: [.init(label: "Undo", prompt: "Undo")])
            }
        )
    }

    /// Moves a file back to its old path, under its old name if that's free.
    private static func putBack(_ now: URL, to was: URL) throws {
        let dir = was.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = FileManager.default.fileExists(atPath: was.path) ? FileOps.uniqueURL(in: dir, name: was.lastPathComponent) : was
        try FileManager.default.moveItem(at: now, to: target)
    }

    /// Puts the last moved files back where they were, or sends the last copies to the Trash.
    static func undo() -> Reply {
        guard let l = last else { return Reply(text: "There's nothing for me to undo.") }
        last = nil
        var back = 0
        for m in l.moves where FileManager.default.fileExists(atPath: m.now.path) {
            if l.op == .copy {
                if (try? FileOps.trash(m.now)) != nil { back += 1 }
            } else if (try? putBack(m.now, to: m.was)) != nil {
                // .move and .trash both go back where they came from
                back += 1
            }
        }
        FileOps.log("undo: \(back) item(s)")
        guard back > 0 else { return Reply(text: "Those files have moved since, so I left them alone.") }
        return Reply(text: l.op == .copy
            ? (back == 1 ? "Moved the copy to the Trash." : "Moved the \(back) copies to the Trash.")
            : "Put \(FileOps.plural(back, "item")) back where \(back == 1 ? "it was" : "they were").")
    }
}
