import Foundation

/// Read-only look at what's using disk space. Uses Spotlight, so it's fast and needs no special access.
enum DiskReport {
    static func run() -> Reply {
        var sections: [String] = []

        if let free = try? Paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let avail = free.volumeAvailableCapacityForImportantUsage, let total = free.volumeTotalCapacity {
            sections.append("Free space: \(FileOps.human(avail)) of \(FileOps.human(Int64(total))).")
        }

        // Biggest single files (over 200 MB)
        let big = FileOps.run("/usr/bin/mdfind", ["-onlyin", Paths.home.path, "kMDItemFSSize > 209715200"]).out
            .split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            .filter { !$0.path.contains("/Library/") && !$0.path.contains(".app/") }
            .map { ($0, FileOps.size($0)) }
            .filter { $0.1 > 0 } // iCloud files that aren't downloaded use no space on this Mac
            .sorted { $0.1 > $1.1 }
        if !big.isEmpty {
            sections.append("Biggest files:\n" + FileOps.bullets(big.map { "\(FileOps.human($0.1)): \(tilde($0.0))" }, max: 6))
        }

        // node_modules folders in projects you haven't touched in 60+ days
        let cutoff = Date().addingTimeInterval(-60 * 86400)
        let found: [URL] = FileOps.run("/usr/bin/mdfind", ["-onlyin", Paths.home.path, "kMDItemFSName == 'node_modules'"]).out
            .split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        let stale: [URL] = found.filter { url in
            let project = url.deletingLastPathComponent()
            return url.path.components(separatedBy: "/node_modules").count == 2 // skip nested ones
                && !url.path.contains("/Library/")
                && FileOps.created(project) < cutoff && modified(project) < cutoff
        }
        let modules: [(URL, Int64)] = stale.prefix(25)
            .map { ($0, FileOps.size($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        if !modules.isEmpty {
            let sum = modules.reduce(Int64(0)) { $0 + $1.1 }
            sections.append("node_modules in projects untouched for 60+ days (\(FileOps.human(sum)) total, safe to delete and reinstall later):\n"
                + FileOps.bullets(modules.map { "\(FileOps.human($0.1)): \(tilde($0.0.deletingLastPathComponent()))" }, max: 6))
        }

        if sections.count <= 1 { sections.append("Nothing unusually big stood out.") }
        sections.append("I'm only reporting. Nothing was deleted.")
        return Reply(text: sections.joined(separator: "\n\n"))
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func tilde(_ url: URL) -> String {
        url.path.replacingOccurrences(of: Paths.home.path, with: "~")
    }
}
