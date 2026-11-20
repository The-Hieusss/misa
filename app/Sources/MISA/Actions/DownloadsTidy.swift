import Foundation

/// Finds downloads you haven't needed in a month and offers to make them disposable.
enum DownloadsTidy {
    static let days = 30

    static func run() -> Reply {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let old = FileOps.contents(of: Paths.downloads)
            .filter { FileOps.added($0) < cutoff }
            .map { ($0, FileOps.size($0)) }
            .sorted { $0.1 > $1.1 }
        guard !old.isEmpty else {
            return Reply(text: "Nothing in Downloads is older than \(days) days. Tidy already.")
        }
        let total = old.reduce(Int64(0)) { $0 + $1.1 }
        let files = old.map(\.0)
        var reply = Reply(text: "\(FileOps.plural(old.count, "item")) in Downloads were added more than \(days) days ago (\(FileOps.human(total))).")

        if DisposableActions.isInstalled {
            reply.confirm = .init(
                title: "Move them to Disposable? They'll go to the Trash in \(DisposableActions.hours) hours unless you keep some.",
                items: old.map { "\($0.0.lastPathComponent) (\(FileOps.human($0.1)))" },
                button: "Move \(old.count)",
                danger: true
            ) {
                DisposableActions.mark(files)
            }
        } else {
            reply.text += "\n\nBiggest:\n" + FileOps.bullets(old.map { "\($0.0.lastPathComponent) (\(FileOps.human($0.1)))" })
            reply.text += "\n\nInstall Disposable Downloads and I can clear these out for you."
        }
        return reply
    }
}
