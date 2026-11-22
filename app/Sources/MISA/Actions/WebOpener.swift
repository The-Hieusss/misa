import AppKit

/// Websites and web searches, opened in your default browser.
/// "open youtube.com", "open gmail", "go to github.com/apple", "search for mac shortcuts".
enum WebOpener {
    /// Sites she knows by name (used when no app has that name).
    private static let sites: [String: String] = [
        "youtube": "https://www.youtube.com", "gmail": "https://mail.google.com", "google": "https://www.google.com",
        "google docs": "https://docs.google.com", "docs": "https://docs.google.com", "google drive": "https://drive.google.com",
        "drive": "https://drive.google.com", "google calendar": "https://calendar.google.com", "google maps": "https://maps.google.com",
        "maps online": "https://maps.google.com", "google sheets": "https://sheets.google.com", "google slides": "https://slides.google.com",
        "github": "https://github.com", "reddit": "https://www.reddit.com", "wikipedia": "https://www.wikipedia.org",
        "amazon": "https://www.amazon.com", "netflix": "https://www.netflix.com", "twitter": "https://x.com", "x": "https://x.com",
        "instagram": "https://www.instagram.com", "facebook": "https://www.facebook.com", "linkedin": "https://www.linkedin.com",
        "chatgpt": "https://chatgpt.com", "claude ai": "https://claude.ai", "twitch": "https://www.twitch.tv",
        "stack overflow": "https://stackoverflow.com", "stackoverflow": "https://stackoverflow.com", "outlook web": "https://outlook.live.com",
        "spotify web": "https://open.spotify.com", "hacker news": "https://news.ycombinator.com", "quizlet": "https://quizlet.com",
        "chegg": "https://www.chegg.com", "leetcode": "https://leetcode.com", "pinterest": "https://www.pinterest.com",
    ]

    /// A bare domain or URL: "youtube.com", "github.com/apple", "https://…". Needs a dot and a letters-only ending.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"(?i)\b(?:https?://)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:/[^\s,]*)?"#)

    /// URLs and domains in the text, keeping their original case (paths can be case-sensitive).
    static func links(in raw: String) -> [URL] {
        let ns = raw as NSString
        return linkPattern.matches(in: raw, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            var s = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".)"))
            // Skip things like "3.5" or file names like "notes.txt" by requiring a real-looking domain ending.
            let host = s.replacingOccurrences(of: #"^(?i)https?://"#, with: "", options: .regularExpression).split(separator: "/").first ?? ""
            guard let tld = host.split(separator: ".").last, tld.count >= 2, !fileEndings.contains(tld.lowercased()) else { return nil }
            if !s.lowercased().hasPrefix("http") { s = "https://" + s }
            return URL(string: s)
        }
    }
    private static let fileEndings: Set<String> = ["txt", "pdf", "png", "jpg", "jpeg", "heic", "mov", "mp4", "doc", "docx", "zip", "swift", "js", "ts", "py", "md", "app"]

    static func isLink(_ s: String) -> Bool { !links(in: s).isEmpty }

    /// A site she knows by name ("youtube", "gmail website").
    static func site(_ name: String) -> URL? {
        var n = name.lowercased()
        for word in [" website", " site", " web page", " page", " dot com"] { n = n.replacingOccurrences(of: word, with: "") }
        n = n.trimmingCharacters(in: .whitespaces)
        return sites[n].flatMap(URL.init(string:))
    }

    /// Short label for a reply: "youtube.com", "github.com/apple".
    static func label(_ url: URL) -> String {
        var s = url.absoluteString.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    static func open(_ urls: [URL]) {
        for u in urls { FileOps.onMain { _ = NSWorkspace.shared.open(u) } }
        FileOps.log("open-web: \(urls.map(label).joined(separator: ", "))")
    }

    // MARK: Search

    /// "search for X", "google X", "search youtube for X", "look up X online". Nil if it isn't a search.
    static func search(_ raw: String) -> Reply? {
        guard let (name, q, url) = searchURL(raw) else { return nil }
        FileOps.onMain { _ = NSWorkspace.shared.open(url) }
        FileOps.log("search: \(name)")
        return Reply(text: "Searching \(name) for “\(q)”.")
    }

    /// The search page for a request, without opening it.
    static func searchURL(_ raw: String) -> (engine: String, query: String, url: URL)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        let engines: [(prefixes: [String], name: String, base: String)] = [
            (["search youtube for ", "youtube search ", "search on youtube for "], "YouTube", "https://www.youtube.com/results?search_query="),
            (["search the web for ", "search google for ", "search online for ", "search for ", "google ", "look up ", "web search "], "Google", "https://www.google.com/search?q="),
        ]
        // "find lofi on youtube", "play study music on youtube"
        if lower.hasSuffix(" on youtube"), let lead = ["find me ", "find ", "search for ", "search ", "look up ", "play ", "put on "].first(where: { lower.hasPrefix($0) }) {
            let q = String(s.dropFirst(lead.count).dropLast(" on youtube".count)).trimmingCharacters(in: .whitespaces)
            if !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://www.youtube.com/results?search_query=" + enc.replacingOccurrences(of: "&", with: "%26").replacingOccurrences(of: "+", with: "%2B")) {
                return ("YouTube", q, url)
            }
        }
        for e in engines {
            guard let p = e.prefixes.first(where: { lower.hasPrefix($0) }) else { continue }
            var q = String(s.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!")))
            for tail in [" online", " on the web", " on google", " for me"] where q.lowercased().hasSuffix(tail) { q = String(q.dropLast(tail.count)) }
            guard !q.isEmpty, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: e.base + enc.replacingOccurrences(of: "&", with: "%26").replacingOccurrences(of: "+", with: "%2B")) else { continue }
            return (e.name, q, url)
        }
        return nil
    }
}
