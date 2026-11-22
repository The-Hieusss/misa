import Foundation

/// What M.I.S.A. says back. Sent to the web view as JSON.
struct Reply {
    struct Suggestion { let label: String; let prompt: String }

    /// A card that must be clicked before anything risky runs.
    struct Confirm {
        let id = UUID().uuidString
        let title: String
        let items: [String]
        let button: String
        /// Red styling for actions that send things to the Trash.
        let danger: Bool
        let run: () -> Reply
    }

    var text: String
    var suggestions: [Suggestion] = []
    var confirm: Confirm? = nil
    /// Files this reply produced, for "Show in Finder".
    var outputs: [URL] = []
    /// Where the dropped files are now, after a move, so "this" keeps pointing at them.
    var replacesFiles: [URL]? = nil
    /// Search results, numbered, so "open 2" or "use 1" can pick one next.
    var found: [URL]? = nil

    var json: [String: Any] {
        var m: [String: Any] = [
            "type": "reply",
            "text": text,
            "suggestions": suggestions.map { ["label": $0.label, "prompt": $0.prompt] },
        ]
        if let c = confirm {
            m["confirm"] = ["id": c.id, "title": c.title, "items": c.items, "button": c.button, "danger": c.danger]
        }
        return m
    }
}

extension Reply.Suggestion {
    static let showInFinder = Reply.Suggestion(label: "Show in Finder", prompt: "Show in Finder")
}
