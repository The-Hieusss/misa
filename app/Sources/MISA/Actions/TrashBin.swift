import Foundation

/// Empties the Trash, after showing what's in it on a confirm card.
///
/// Finder does the work (through AppleScript), because ~/.Trash is privacy-protected and other
/// disks keep their own Trash folders. The first time, macOS asks to let M.I.S.A. control Finder.
enum TrashBin {
    /// How many names to list on the confirm card.
    private static let shown = 40

    private static func finder(_ script: String) -> (ok: Bool, out: String, err: String) {
        let r = FileOps.run("/usr/bin/osascript", ["-e", "tell application \"Finder\"", "-e", script, "-e", "end tell"])
        return (r.status == 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines), r.err)
    }

    private static func permissionHelp(_ err: String) -> Reply? {
        // -1743: the user (or macOS) hasn't allowed M.I.S.A. to control Finder.
        guard err.contains("-1743") || err.localizedCaseInsensitiveContains("not authorized") else { return nil }
        return Reply(text: "macOS didn't let me control Finder, which I need to empty the Trash. Turn on Finder under M.I.S.A. in System Settings > Privacy & Security > Automation, then ask again.")
    }

    static func empty() -> Reply {
        let count = finder("count items of trash")
        guard count.ok, let n = Int(count.out) else {
            if let help = permissionHelp(count.err) { return help }
            FileOps.log("trash: couldn't read the Trash: \(count.err)")
            return Reply(text: "I couldn't look inside the Trash.")
        }
        guard n > 0 else { return Reply(text: "The Trash is already empty. 🧹") }

        // Names, one per line ("name of every item" joins with commas, which names can contain).
        let names = finder("""
            set out to ""
            repeat with f in (items 1 thru \(min(n, shown)) of trash)
            set out to out & (name of f) & linefeed
            end repeat
            return out
            """).out.split(separator: "\n").map(String.init)
        var items = names
        if n > names.count { items.append("…and \(n - names.count) more") }

        return Reply(
            text: "The Trash has \(FileOps.plural(n, "item")).",
            confirm: .init(
                title: "Empty the Trash? This deletes them for good.",
                items: items,
                button: "Empty \(n)",
                danger: true
            ) {
                let r = finder("empty trash")
                guard r.ok else {
                    if let help = permissionHelp(r.err) { return help }
                    FileOps.log("trash: empty failed: \(r.err)")
                    let left = Int(finder("count items of trash").out) ?? n
                    return Reply(text: "Finder couldn't empty everything (\(FileOps.plural(left, "item")) left). Some may be locked or still in use.")
                }
                FileOps.log("trash: emptied \(n) item(s)")
                return Reply(text: "Emptied the Trash (\(FileOps.plural(n, "item"))).")
            }
        )
    }
}
