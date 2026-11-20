import Foundation

/// Screenshot janitor: gets screenshots off the Desktop and clears out old ones.
enum Screenshots {
    static let keepDays = 7

    private static var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }

    /// Moves screenshots and screen recordings from the Desktop into ~/Screenshots/<year-month>/.
    static func tidy() -> Reply {
        let shots = FileOps.contents(of: Paths.desktop).filter(FileOps.isScreenshot)
        guard !shots.isEmpty else {
            return Reply(text: "No screenshots on your Desktop. 👍",
                         suggestions: [.init(label: "Save new ones to a folder", prompt: "Save screenshots to a folder")])
        }
        let size = shots.reduce(Int64(0)) { $0 + FileOps.size($1) }
        return Reply(
            text: "Found \(FileOps.plural(shots.count, "screenshot")) on your Desktop (\(FileOps.human(size))).",
            confirm: .init(
                title: "Move them to ~/Screenshots, sorted by month?",
                items: shots.map(\.lastPathComponent),
                button: "Move \(shots.count)",
                danger: false
            ) {
                var moved = 0
                for s in shots {
                    let month = monthFormatter.string(from: FileOps.created(s))
                    if (try? FileOps.move(s, into: Paths.screenshots.appendingPathComponent(month))) != nil { moved += 1 }
                }
                FileOps.log("screenshots: moved \(moved) from Desktop")
                return Reply(
                    text: "Done. Moved \(FileOps.plural(moved, "screenshot")) to ~/Screenshots.",
                    suggestions: [.showInFinder, .init(label: "Save new ones there", prompt: "Save screenshots to a folder")],
                    outputs: [Paths.screenshots]
                )
            }
        )
    }

    /// Sends screenshots older than a week (in ~/Screenshots) to the Trash.
    static func trashOld() -> Reply {
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        var old: [URL] = []
        if let e = FileManager.default.enumerator(at: Paths.screenshots, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in e where FileOps.kind(url) != .folder && FileOps.created(url) < cutoff {
                old.append(url)
            }
        }
        guard !old.isEmpty else {
            return Reply(text: "No screenshots older than \(keepDays) days in ~/Screenshots.")
        }
        let size = old.reduce(Int64(0)) { $0 + FileOps.size($1) }
        return Reply(
            text: "\(FileOps.plural(old.count, "screenshot")) in ~/Screenshots are older than \(keepDays) days (\(FileOps.human(size))).",
            confirm: .init(
                title: "Move them to the Trash?",
                items: old.map(\.lastPathComponent),
                button: "Trash \(old.count)",
                danger: true
            ) {
                var done = 0
                for f in old where (try? FileOps.trash(f)) != nil { done += 1 }
                FileOps.log("screenshots: trashed \(done) older than \(keepDays) days")
                return Reply(text: "Moved \(FileOps.plural(done, "screenshot")) to the Trash.")
            }
        )
    }

    /// Tells macOS to save new screenshots to ~/Screenshots instead of the Desktop.
    static func saveToFolder() -> Reply {
        let current = FileOps.run("/usr/bin/defaults", ["read", "com.apple.screencapture", "location"]).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if (current as NSString).expandingTildeInPath == Paths.screenshots.path {
            return Reply(text: "New screenshots already save to ~/Screenshots.")
        }
        return Reply(
            text: "Right now new screenshots land on your Desktop.",
            confirm: .init(
                title: "Save new screenshots to ~/Screenshots instead?",
                items: ["You can change it back in the Screenshot app (⌘⇧5 → Options)."],
                button: "Change it",
                danger: false
            ) {
                try? FileManager.default.createDirectory(at: Paths.screenshots, withIntermediateDirectories: true)
                let r = FileOps.run("/usr/bin/defaults", ["write", "com.apple.screencapture", "location", Paths.screenshots.path])
                _ = FileOps.run("/usr/bin/killall", ["SystemUIServer"])
                guard r.status == 0 else { return Reply(text: "That didn't work: \(r.err)") }
                FileOps.log("screenshots: save location set to \(Paths.screenshots.path)")
                return Reply(text: "Done. New screenshots now save to ~/Screenshots.",
                             suggestions: [.init(label: "Tidy my Desktop", prompt: "Tidy my screenshots")])
            }
        )
    }
}
