import EventKit
import UserNotifications

/// Finding, changing and deleting calendar events and reminders (the R, U and D of Agenda).
///
///   "when is my dentist appointment"
///   "move my dentist appointment to Friday at 4", "reschedule study group to next Monday"
///   "push my meeting back 30 minutes", "move the exam earlier by an hour"
///   "make the dentist appointment 2 hours long", "extend study group by 30 minutes"
///   "rename dentist to dentist cleaning"
///   "change the reminder to call mom to 7pm"
///   "cancel tomorrow's meeting", "delete the reminder to buy milk"
///
/// Every change and delete shows a confirm card first. Her own notifications move with it.
extension Agenda {
    enum Kind { case event, reminder, either }

    /// A found item, or what to say instead.
    enum Lookup { case found(Item), reply(Reply) }

    /// A found event or reminder.
    enum Item {
        case event(EKEvent)
        case reminder(EKReminder)

        var title: String {
            switch self {
            case .event(let e): return e.title ?? "Untitled"
            case .reminder(let r): return r.title ?? "Untitled"
            }
        }

        /// "“Dentist”, Fri, Nov 27, 3:00 – 4:00 PM"
        var line: String {
            switch self {
            case .event(let e):
                if e.isAllDay { return "“\(title)”, \(describe(e.startDate, time: false)) (all day)" }
                return "“\(title)”, \(describe(e.startDate)) – \(e.endDate.formatted(date: .omitted, time: .shortened))"
            case .reminder(let r):
                guard let d = r.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }) else { return "“\(title)” (no due date)" }
                return "“\(title)”, due \(describe(d, time: r.dueDateComponents?.hour != nil))"
            }
        }
    }

    // MARK: Routing

    /// Changes, deletes and "when is X". Nil if the request isn't one of those.
    static func editRoute(_ t: String, raw: String) -> (() -> Reply)? {
        let low = raw.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"^\s*(?:hey misa[,!]?\s*)?(?:please\s+|can you\s+|could you\s+)*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?")))
        let w = " \(t) "
        func has(_ s: String...) -> Bool { s.contains { w.contains(" \($0) ") } }
        guard !has("timer", "focus", "pomodoro", "countdown", "file", "files", "folder", "download", "downloads", "screenshot", "screenshots",
                   "window", "volume", "brightness", "music", "song", "playlist") else { return nil }
        let kind: Kind = has("reminder", "reminders", "to do", "todo") ? .reminder
            : has("event", "meeting", "appointment", "calendar", "class", "exam", "lecture", "call", "lunch", "dinner", "session", "interview", "party", "game", "practice") ? .event : .either
        /// Only claim requests without agenda words when something by that name actually exists.
        func claim(_ target: String) -> Bool {
            if kind != .either { return true }
            if allowedQuietly(.event), !find(target, kind: .event).isEmpty { return true }
            if allowedQuietly(.reminder), !find(target, kind: .reminder).isEmpty { return true }
            return false
        }
        func match(_ p: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: low, range: NSRange(low.startIndex..., in: low)) else { return nil }
            return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: low).map { String(low[$0]) } ?? "" }
        }

        // Delete: "cancel tomorrow's meeting", "delete the reminder to buy milk", "remove dentist from my calendar"
        if let g = match(#"^(?:remove|delete|cancel|clear|drop|erase|get rid of|take off)\s+(.+)$"#) {
            let target = g[0]
            guard !["this", "it", "that", "them", "these", "those", "everything", "all"].contains(target), claim(target) else { return nil }
            return { delete(target, kind: kind) }
        }
        // Rename: "rename dentist to dentist cleaning", "change the name of X to Y"
        if let g = match(#"^(?:rename|retitle|change the (?:name|title) of|change the name of)\s+(.+?)\s+to\s+(.+)$"#), claim(g[0]) {
            return { rename(g[0], to: g[1], kind: kind) }
        }
        // Shift: "push my meeting back 30 minutes", "move the exam earlier by an hour", "push back study group by an hour"
        if let g = match(#"^(?:push|move|bump|shift|delay|pull)\s+(?:(back|forward|up)\s+)?(.+?)\s+(back|later|forward|earlier|up|ahead)?\s*(?:by\s+)?((?:an?|one|half an?|\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h|minutes?|mins?|m|days?))$"#) {
            let dir = (g[0].isEmpty ? g[2] : g[0])
            guard !dir.isEmpty, claim(g[1]) else { return nil }
            let amount = duration(g[3])
            let later = ["back", "later"].contains(dir)
            return { shift(g[1], by: later ? amount : -amount, kind: kind) }
        }
        // Length: "make dentist 2 hours long", "extend study group by 30 minutes", "shorten the meeting by 15 minutes"
        if let g = match(#"^(extend|lengthen|shorten)\s+(.+?)\s+by\s+(.+)$"#), claim(g[1]) {
            let d = duration(g[2])
            return { resize(g[1], change: g[0] == "shorten" ? -d : d, to: nil) }
        }
        if let g = match(#"^make\s+(.+?)\s+((?:an?|one|half an?|\d+(?:\.\d+)?)\s*(?:hours?|hrs?|minutes?|mins?))(?:\s+long)?$"#), claim(g[0]) {
            let d = duration(g[1])
            return { resize(g[0], change: 0, to: d) }
        }
        // Reschedule: "move my dentist appointment to friday at 4", "reschedule study group to monday",
        // "change the reminder to call mom to 7pm"
        if let g = match(#"^(?:move|reschedule|change|switch|shift|push|bump|postpone|set)\s+(.+)\s+to\s+(.+)$"#), let w = when(in: g[1]) {
            let rescheduleWord = low.hasPrefix("reschedule") || low.hasPrefix("postpone")
            guard rescheduleWord || claim(g[0]) else { return nil }
            return { reschedule(g[0], to: w, phrase: g[1], kind: kind) }
        }
        // Read one: "when is my dentist appointment", "what time is the exam"
        if let g = match(#"^(?:when(?:'s| is| are| was)|what time is|what time's|what day is)\s+(.+)$"#),
           !["it", "that", "this", "now", "today", "tomorrow", "the time", "my next", "the next"].contains(where: { g[0] == $0 || g[0].hasPrefix($0 + " ") }),
           !g[0].hasPrefix("next "), g[0].count >= 3, claim(g[0]) {
            return { whenIs(g[0], kind: kind) }
        }
        return nil
    }

    /// "30 minutes", "an hour", "half an hour", "2 days" → seconds.
    static func duration(_ s: String) -> TimeInterval {
        let t = s.lowercased()
        if t.contains("half") { return 1800 }
        if let r = t.range(of: #"(\d+(?:\.\d+)?|an?|one)\s*days?"#, options: .regularExpression) {
            let n = Double(t[r].split(separator: " ").first.map(String.init) ?? "") ?? 1
            return n * 86400
        }
        let numeric = t.replacingOccurrences(of: #"\b(?:an|a|one)\b"#, with: "1", options: .regularExpression)
        return FocusTimer.parseDuration(numeric) ?? 3600
    }

    // MARK: Finding

    /// The title words left once "my", "the", "event", "from my calendar" and any day are taken out,
    /// plus that day (to narrow the search).
    private static func clean(_ target: String) -> (words: String, day: Date?) {
        var s = target
        var day: Date?
        // "tomorrow's meeting", "friday's class"
        s = s.replacingOccurrences(of: #"\b(today|tomorrow|tonight|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday)'s\b"#, with: "$1", options: .regularExpression)
        if let w = when(in: s) {
            day = Calendar.current.startOfDay(for: w.date)
            s.replaceSubrange(w.range, with: " ")
        }
        let junk = [#"\b(?:from|on|in|off)\s+(?:my|the)\s+(?:calendar|schedule|reminders|reminders list)\b"#, #"^(?:my|the|our|this|that|a)\s+"#,
                    #"^(?:reminder|event|calendar event)\s+(?:to|about|for|called|named)?\s*"#, #"\s+(?:reminder|event)$"#,
                    #"^(?:to|about|for|called|named)\s+"#, #"\s+(?:on|at|for|this|next)$"#]
        for _ in 0..<2 { for p in junk { s = s.replacingOccurrences(of: p, with: "", options: .regularExpression) } }
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        // "dentist appointment" should find "Dentist", not every appointment.
        let trimmed = s.replacingOccurrences(of: #"\s+(?:appointment|meeting|event|session)$"#, with: "", options: .regularExpression)
        return (trimmed.isEmpty ? s : trimmed, day)
    }

    /// Events from yesterday to four months out, and open reminders, whose title matches best.
    static func find(_ target: String, kind: Kind) -> [Item] {
        let (words, day) = clean(target)
        var items: [Item] = []
        if kind != .reminder, allowedQuietly(.event) {
            let cal = Calendar.current
            let start = day ?? cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
            let end = day.map { cal.date(byAdding: .day, value: 1, to: $0)! } ?? cal.date(byAdding: .day, value: 120, to: start)!
            let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
            let generic = ["", "meeting", "event", "appointment", "class", "thing", "plans", "call"].contains(words)
            var hits = generic && day != nil ? events.filter { words.isEmpty || ($0.title ?? "").lowercased().contains(words) || events.count == 1 } : SystemControls.best(words, events) { $0.title ?? "" }
            if hits.isEmpty, generic, day != nil { hits = events }
            items += hits.map { .event($0) }
        }
        if kind != .event, allowedQuietly(.reminder), !words.isEmpty {
            items += SystemControls.best(words, fetchIncomplete()) { $0.title ?? "" }.map { .reminder($0) }
        }
        return items
    }

    /// Asks for access if needed, then finds; or explains what's missing.
    private static func lookup(_ target: String, kind: Kind) -> Lookup {
        if kind != .reminder, !allowed(.event) { return .reply(noAccess(.event)) }
        if kind != .event, kind == .reminder || allowedQuietly(.reminder) || EKEventStore.authorizationStatus(for: .reminder) == .notDetermined, !allowed(.reminder) {
            return .reply(noAccess(.reminder))
        }
        let hits = find(target, kind: kind)
        let name = clean(target).words
        guard let first = hits.first else {
            let what = kind == .reminder ? "an open reminder" : kind == .event ? "an event" : "an event or reminder"
            return .reply(Reply(text: "I can't find \(what) called “\(name.isEmpty ? target : name)”.",
                                  suggestions: [.init(label: "What's on this week?", prompt: "What's on my calendar this week?"), .init(label: "My reminders", prompt: "What are my reminders?")]))
        }
        if hits.count > 1 {
            // Several with that name: let a day pick one ("… on Fri, Nov 28").
            let options = hits.prefix(4).map { item -> Reply.Suggestion in
                switch item {
                case .event(let e): return .init(label: "\(item.title), \(describe(e.startDate, time: !e.isAllDay))", prompt: "")
                case .reminder: return .init(label: "Reminder: \(item.title)", prompt: "")
                }
            }
            return .reply(Reply(text: "I found \(hits.count): \(options.map(\.label).joined(separator: "; ")). Which one? Say it with the day, like “\(hits[0].title) on \(describeDay(hits[0]))”."))
        }
        return .found(first)
    }

    private static func describeDay(_ item: Item) -> String {
        if case .event(let e) = item { return e.startDate.formatted(.dateTime.weekday(.wide)) }
        return "today"
    }

    // MARK: Read one

    static func whenIs(_ target: String, kind: Kind) -> Reply {
        switch lookup(target, kind: kind) {
        case .reply(let r): return r
        case .found(let item):
            switch item {
            case .event(let e):
                let mins = Int(e.startDate.timeIntervalSinceNow / 60)
                let soon = !e.isAllDay && mins > 0 && mins < 24 * 60 ? " (in \(FocusTimer.describe(Double(mins) * 60)))" : ""
                return Reply(text: "\(item.line)\(soon)\(e.location.map { " at \($0)" } ?? "").",
                             suggestions: [.init(label: "Cancel it", prompt: "Cancel \(item.title) on \(describeDay(item))")])
            case .reminder:
                return Reply(text: "Reminder \(item.line).", suggestions: [.init(label: "Mark done", prompt: "Mark \(item.title) done")])
            }
        }
    }

    // MARK: Update

    static func reschedule(_ target: String, to w: When, phrase: String, kind: Kind) -> Reply {
        switch lookup(target, kind: kind) {
        case .reply(let r): return r
        case .found(let item):
            switch item {
            case .event(let e):
                let cal = Calendar.current
                // A new day without a time keeps the old time of day; a new time without a day keeps the day.
                var start = w.date
                let saidDay = phrase.range(of: #"today|tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next|week|\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\d{1,2}/\d{1,2}|\bin \d"#, options: .regularExpression) != nil
                if !w.hasTime && !e.isAllDay {
                    let t = cal.dateComponents([.hour, .minute], from: e.startDate)
                    start = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: w.date) ?? w.date
                } else if w.hasTime && !saidDay {
                    let t = cal.dateComponents([.hour, .minute], from: w.date)
                    start = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: e.startDate) ?? w.date
                }
                let length = w.duration ?? e.endDate.timeIntervalSince(e.startDate)
                let newLine = e.isAllDay && !w.hasTime ? "\(describe(start, time: false)) (all day)" : "\(describe(start)) – \(start.addingTimeInterval(length).formatted(date: .omitted, time: .shortened))"
                return Reply(text: "Here's the change:", confirm: .init(title: "Move this event?", items: [item.line, "→ \(newLine)"] + repeats(e), button: "Move it", danger: false) {
                    if e.isAllDay && w.hasTime { e.isAllDay = false }
                    e.startDate = e.isAllDay ? cal.startOfDay(for: start) : start
                    e.endDate = e.isAllDay ? e.startDate : start.addingTimeInterval(length)
                    return save(e, done: "Moved “\(item.title)” to \(e.isAllDay ? describe(start, time: false) : describe(start)). 📅")
                })
            case .reminder(let r):
                return Reply(text: "Here's the change:", confirm: .init(title: "Change this reminder?", items: [item.line, "→ due \(describe(w.date, time: w.hasTime))"], button: "Change it", danger: false) {
                    let parts: Set<Calendar.Component> = w.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
                    r.dueDateComponents = Calendar.current.dateComponents(parts, from: w.date)
                    return save(r, ping: w.hasTime ? w.date : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: w.date),
                                done: "“\(item.title)” is now due \(describe(w.date, time: w.hasTime)). ✅")
                })
            }
        }
    }

    static func shift(_ target: String, by seconds: TimeInterval, kind: Kind) -> Reply {
        switch lookup(target, kind: kind) {
        case .reply(let r): return r
        case .found(let item):
            let amount = FocusTimer.describe(abs(seconds))
            let way = seconds > 0 ? "later" : "earlier"
            switch item {
            case .event(let e):
                let start = e.startDate.addingTimeInterval(seconds), end = e.endDate.addingTimeInterval(seconds)
                return Reply(text: "Here's the change:", confirm: .init(title: "Move it \(amount) \(way)?", items: [item.line, "→ \(describe(start)) – \(end.formatted(date: .omitted, time: .shortened))"] + repeats(e), button: "Move it", danger: false) {
                    e.startDate = start
                    e.endDate = end
                    return save(e, done: "Moved “\(item.title)” \(amount) \(way), to \(describe(start)). 📅")
                })
            case .reminder(let r):
                guard let due = r.dueDateComponents.flatMap({ Calendar.current.date(from: $0) }) else { return Reply(text: "“\(item.title)” has no due date to move.") }
                let newDue = due.addingTimeInterval(seconds)
                return Reply(text: "Here's the change:", confirm: .init(title: "Change this reminder?", items: [item.line, "→ due \(describe(newDue))"], button: "Change it", danger: false) {
                    r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: newDue)
                    return save(r, ping: newDue, done: "“\(item.title)” is now due \(describe(newDue)). ✅")
                })
            }
        }
    }

    static func resize(_ target: String, change: TimeInterval, to length: TimeInterval?) -> Reply {
        switch lookup(target, kind: .event) {
        case .reply(let r): return r
        case .found(let item):
            guard case .event(let e) = item, !e.isAllDay else { return Reply(text: "“\(item.title)” is an all-day event, so it has no length to change.") }
            let newLength = max(300, length ?? (e.endDate.timeIntervalSince(e.startDate) + change))
            let end = e.startDate.addingTimeInterval(newLength)
            return Reply(text: "Here's the change:", confirm: .init(title: "Change how long it is?", items: [item.line, "→ \(describe(e.startDate)) – \(end.formatted(date: .omitted, time: .shortened)) (\(FocusTimer.describe(newLength)))"] + repeats(e), button: "Change it", danger: false) {
                e.endDate = end
                return save(e, done: "“\(item.title)” now runs \(FocusTimer.describe(newLength)), until \(end.formatted(date: .omitted, time: .shortened)). 📅")
            })
        }
    }

    static func rename(_ target: String, to newName: String, kind: Kind) -> Reply {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let nice = name.prefix(1).uppercased() + name.dropFirst()
        guard !name.isEmpty else { return Reply(text: "What should it be called?") }
        switch lookup(target, kind: kind) {
        case .reply(let r): return r
        case .found(let item):
            return Reply(text: "Here's the change:", confirm: .init(title: "Rename it?", items: [item.line, "→ “\(nice)”"], button: "Rename", danger: false) {
                switch item {
                case .event(let e):
                    e.title = nice
                    return save(e, done: "Renamed it to “\(nice)”. 📅")
                case .reminder(let r):
                    r.title = nice
                    let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    return save(r, ping: due.map { r.dueDateComponents?.hour != nil ? $0 : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: $0)! }, done: "Renamed it to “\(nice)”. ✅")
                }
            })
        }
    }

    // MARK: Delete

    static func delete(_ target: String, kind: Kind) -> Reply {
        switch lookup(target, kind: kind) {
        case .reply(let r): return r
        case .found(let item):
            switch item {
            case .event(let e):
                return Reply(text: "Here's the event:", confirm: .init(title: "Delete this event?", items: [item.line, "From \(e.calendar.title)"] + repeats(e), button: "Delete", danger: true) {
                    let id = e.eventIdentifier ?? ""
                    do { try store.remove(e, span: .thisEvent, commit: true) } catch { return Reply(text: "Calendar wouldn't delete it (\(error.localizedDescription)).") }
                    Notices.cancelEvent(id)
                    FileOps.log("event deleted: \(item.title)")
                    return Reply(text: "Deleted “\(item.title)” from your calendar. 🗑️")
                })
            case .reminder(let r):
                return Reply(text: "Here's the reminder:", confirm: .init(title: "Delete this reminder?", items: [item.line, "From \(r.calendar.title)"], button: "Delete", danger: true) {
                    let id = r.calendarItemIdentifier
                    do { try store.remove(r, commit: true) } catch { return Reply(text: "Reminders wouldn't delete it (\(error.localizedDescription)).") }
                    Notices.cancel(id)
                    FileOps.log("reminder deleted: \(item.title)")
                    return Reply(text: "Deleted the reminder “\(item.title)”. 🗑️",
                                 suggestions: [.init(label: "My reminders", prompt: "What are my reminders?")])
                })
            }
        }
    }

    // MARK: Saving

    /// A repeating event: say that only this one changes.
    private static func repeats(_ e: EKEvent) -> [String] { e.hasRecurrenceRules ? ["Only this one (it repeats)"] : [] }

    private static func save(_ e: EKEvent, done: String) -> Reply {
        do { try store.save(e, span: .thisEvent, commit: true) } catch { return Reply(text: "Calendar wouldn't save the change (\(error.localizedDescription)).") }
        let id = e.eventIdentifier ?? ""
        Notices.cancelEvent(id)
        if !e.isAllDay { Notices.headsUp(id: id, title: e.title ?? "Event", starts: e.startDate) }
        FileOps.log("event changed: \(e.title ?? "") @ \(e.startDate!)")
        return Reply(text: done)
    }

    private static func save(_ r: EKReminder, ping: Date?, done: String) -> Reply {
        do { try store.save(r, commit: true) } catch { return Reply(text: "Reminders wouldn't save the change (\(error.localizedDescription)).") }
        Notices.cancel(r.calendarItemIdentifier)
        if let ping, ping > Date() { Notices.remind(id: r.calendarItemIdentifier, title: r.title ?? "Reminder", at: ping) }
        FileOps.log("reminder changed: \(r.title ?? "")")
        return Reply(text: done)
    }
}
