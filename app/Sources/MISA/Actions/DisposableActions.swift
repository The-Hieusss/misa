import Foundation

/// Works with the Disposable Downloads kit: ~/Disposable is emptied into the Trash on a timer.
enum DisposableActions {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.home
            .appendingPathComponent("Library/LaunchAgents/com.user.disposable.cleanup.plist").path)
    }

    static var hours: Int {
        let config = Paths.home.appendingPathComponent("Library/Application Support/Disposable/config")
        guard let s = try? String(contentsOf: config, encoding: .utf8),
              let line = s.split(separator: "\n").first(where: { $0.hasPrefix("HOURS=") }),
              let h = Int(line.dropFirst("HOURS=".count)) else { return 24 }
        return h
    }

    private static let notInstalled = Reply(
        text: "Disposable Downloads isn't installed on this Mac, so nothing would empty ~/Disposable. Install it from github.com/The-Hieusss/disposable-downloads first."
    )

    /// What's in Disposable and when each item goes to the Trash.
    static func status() -> Reply {
        guard FileManager.default.fileExists(atPath: Paths.disposable.path) else { return notInstalled }
        let now = Date()
        let items = FileOps.contents(of: Paths.disposable)
            .map { ($0.lastPathComponent, FileOps.arrived($0).addingTimeInterval(TimeInterval(hours * 3600))) }
            .sorted { $0.1 < $1.1 }
        if items.isEmpty { return Reply(text: "Disposable is empty. Nothing is scheduled for the Trash.") }

        let lines = items.map { "\($0.0): \(timeLeft(until: $0.1, from: now))" }
        return Reply(
            text: "\(FileOps.plural(items.count, "item")) in Disposable (\(hours)-hour timer):\n" + FileOps.bullets(lines, max: 8),
            suggestions: [.init(label: "Keep a file", prompt: "Keep ")]
        )
    }

    /// Moves files into ~/Disposable. Reversible until the timer runs out.
    static func mark(_ files: [URL]) -> Reply {
        guard isInstalled else { return notInstalled }
        var moved: [String] = [], failed: [String] = []
        for f in files where f.deletingLastPathComponent().standardizedFileURL != Paths.disposable.standardizedFileURL {
            do {
                try FileOps.move(f, into: Paths.disposable)
                FileOps.log("marked: \(f.path)", to: Paths.disposableLog)
                moved.append(f.lastPathComponent)
            } catch {
                failed.append(f.lastPathComponent)
            }
        }
        if moved.isEmpty && failed.isEmpty { return Reply(text: "Those are already in Disposable.") }
        var text = moved.isEmpty ? "" : "Moved \(FileOps.plural(moved.count, "item")) to Disposable. \(moved.count == 1 ? "It goes" : "They go") to the Trash in \(hours) hours:\n" + FileOps.bullets(moved)
        if !failed.isEmpty { text += "\n\nCouldn't move: " + failed.joined(separator: ", ") }
        return Reply(text: text, suggestions: [.init(label: "What's in Disposable?", prompt: "What's in Disposable?")])
    }

    /// Takes a file back out of Disposable into Downloads.
    static func keep(matching query: String) -> Reply {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let items = FileOps.contents(of: Paths.disposable)
        guard !q.isEmpty else {
            return Reply(text: "Which file? Say \"keep\" plus part of its name, e.g. \"keep homework 6\".")
        }
        let matches = items.filter { $0.lastPathComponent.lowercased().contains(q) }
        switch matches.count {
        case 0:
            return Reply(text: "Nothing in Disposable matches \"\(query)\".", suggestions: [.init(label: "What's in Disposable?", prompt: "What's in Disposable?")])
        case 1:
            do {
                let dest = try FileOps.move(matches[0], into: Paths.downloads)
                FileOps.log("kept: \(matches[0].lastPathComponent) → \(dest.path)", to: Paths.disposableLog)
                return Reply(text: "Saved \(matches[0].lastPathComponent). It's back in Downloads and won't be trashed.",
                             suggestions: [.showInFinder], outputs: [dest])
            } catch {
                return Reply(text: "Couldn't move it: \(error.localizedDescription)")
            }
        default:
            return Reply(text: "Several files match \"\(query)\". Which one?\n" + FileOps.bullets(matches.map(\.lastPathComponent)),
                         suggestions: matches.prefix(4).map { .init(label: $0.lastPathComponent, prompt: "Keep \($0.lastPathComponent)") })
        }
    }

    private static func timeLeft(until date: Date, from now: Date) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "goes to the Trash on the next hourly check" }
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "trashed in \(h)h \(m)m" : "trashed in \(m)m"
    }
}
