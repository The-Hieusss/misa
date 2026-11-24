import EventKit
import UserNotifications

/// Your Calendar and Reminders (the Mac's own, synced through iCloud like everywhere else).
///
///   "what's on today", "what's next", "what do I have tomorrow", "what are my reminders"
///   "remind me to submit HW 6 at 9pm", "add dentist to my calendar Friday at 3pm for an hour"
///   "mark submit HW 6 done"
///
/// New events and reminders show a confirm card first. M.I.S.A. then sends her own notification
/// when a reminder is due (with Done and Snooze buttons) and 10 minutes before an event.
enum Agenda {
    static let store = EKEventStore()

    // MARK: Routing

    static func route(_ t: String, raw: String) -> (() -> Reply)? {
        let w = " \(t) "
        func has(_ s: String...) -> Bool { s.contains { w.contains(" \($0) ") } }

        // Changing, deleting, or finding one: "move my dentist appointment to Friday", "cancel tomorrow's meeting"
        if let action = editRoute(t, raw: raw) { return action }

        // Reminders
        if t.hasPrefix("remind me") || t.hasPrefix("set a reminder") || t.hasPrefix("add a reminder") || t.hasPrefix("create a reminder")
            || t.hasPrefix("new reminder") || t.hasPrefix("make a reminder") {
            return { newReminder(raw) }
        }
        if (has("reminders", "reminder", "to do", "todo", "to dos", "todos", "to do list") && has("what", "show", "list", "my", "any", "whats", "what's"))
            || ["what do i need to do", "what do i have to do", "what's due", "whats due", "what is due"].contains(where: t.hasPrefix) {
            return { reminders() }
        }
        if let m = t.range(of: #"^(?:mark|check off|complete|cross off|tick off|finish(?:ed)?|i finished|i did|done with|i'm done with|im done with) (.+?)(?: as)?(?: done| complete| completed| finished)?$"#, options: .regularExpression),
           !has("timer", "focus", "break") {
            let what = String(t[m]).replacingOccurrences(of: #"^(?:mark|check off|complete|cross off|tick off|finish(?:ed)?|i finished|i did|done with|i'm done with|im done with) "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?: as)?(?: done| complete| completed| finished)$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^(?:the |my )?(?:reminder )?(?:to )?"#, with: "", options: .regularExpression)
            if !what.isEmpty, t.hasPrefix("mark") || t.hasPrefix("check off") || t.hasPrefix("cross off") || t.hasPrefix("tick off") || has("reminder") || hasReminder(like: what) {
                return { complete(what) }
            }
        }

        // New events
        let eventWords = has("event", "meeting", "appointment", "calendar")
        let creating = ["add ", "schedule ", "create ", "put ", "book ", "make ", "new event", "set up "].contains(where: t.hasPrefix)
        if creating && (eventWords || t.hasPrefix("schedule ") || t.hasPrefix("book ")) && !has("reminder", "timer", "focus") {
            return { newEvent(raw) }
        }

        // Looking at the calendar
        if has("whats next", "what's next", "next event", "next meeting", "next class", "next appointment", "what's my next", "whats my next", "when is my next", "when's my next") {
            return { next() }
        }
        if has("calendar", "schedule", "agenda", "events", "meetings", "classes")
            && has("what", "what's", "whats", "show", "my", "today", "tomorrow", "week", "any")
            || ["what do i have", "what's on", "whats on", "am i free", "am i busy", "do i have anything"].contains(where: t.hasPrefix) {
            return { agenda(t) }
        }
        return nil
    }

    // MARK: Permission

    /// Asks once; waits for the answer (call off the main thread).
    static func allowed(_ type: EKEntityType) -> Bool {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return true
        case .notDetermined:
            let done = DispatchSemaphore(value: 0)
            var ok = false
            let finish: (Bool, Error?) -> Void = { granted, _ in ok = granted; done.signal() }
            if type == .event { store.requestFullAccessToEvents(completion: finish) } else { store.requestFullAccessToReminders(completion: finish) }
            done.wait()
            // A store made before access was granted doesn't see your calendars or lists until it reloads.
            if ok { store.reset() }
            return ok
        default: return false
        }
    }

    static func noAccess(_ type: EKEntityType) -> Reply {
        let what = type == .event ? "Calendars" : "Reminders"
        return Reply(text: "I need access to your \(what). Turn on M.I.S.A. in System Settings > Privacy & Security > \(what) (with full access), then ask again.")
    }

    // MARK: Dates in plain English

    struct When {
        var date: Date
        var hasTime: Bool
        var duration: TimeInterval?
        var range: Range<String.Index>
    }

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// "tomorrow at 3pm", "Friday 9-10am", "in 20 minutes", "Dec 5". Nil without a date.
    static func when(in text: String) -> When? {
        // "in 20 minutes", "in an hour", "in half an hour" (the date detector misses these)
        if let r = text.range(of: #"(?i)\bin (?:\d+(?:\.\d+)?|an?|half an?|one) (?:minutes?|mins?|hours?|hrs?)\b"#, options: .regularExpression) {
            let phrase = text[r].lowercased()
            if phrase.contains("half") { return When(date: Date().addingTimeInterval(1800), hasTime: true, duration: nil, range: r) }
            let numeric = phrase.replacingOccurrences(of: #"\b(?:an|a|one)\b"#, with: "1", options: .regularExpression)
            if let secs = FocusTimer.parseDuration(numeric) { return When(date: Date().addingTimeInterval(secs), hasTime: true, duration: nil, range: r) }
        }
        let ns = NSRange(text.startIndex..., in: text)
        guard let m = detector.firstMatch(in: text, range: ns), var date = m.date, var r = Range(m.range, in: text) else { return bareHour(in: text) }
        // Take in a leading "at"/"on"/"due" so it doesn't end up in the title.
        if let lead = text[..<r.lowerBound].range(of: #"(?i)\b(?:at|on|by|due)\s+$"#, options: .regularExpression) { r = lead.lowerBound..<r.upperBound }
        let phrase = text[r].lowercased()
        let clock = phrase.range(of: #"\d\s*(?:am|pm|a\.m|p\.m)|\d:\d\d|\bat \d{1,2}\b"#, options: .regularExpression) != nil
        let hasTime = clock || phrase.range(of: #"noon|midnight|morning|afternoon|evening|tonight|night"#, options: .regularExpression) != nil
        // "due Friday" comes back as a span from now until Friday: Friday is what was meant.
        var duration: TimeInterval? = m.duration > 0 ? m.duration : nil
        if !hasTime, let d = duration { date = date.addingTimeInterval(d); duration = nil }
        // "at 3" with no am/pm: 1 to 6 o'clock means the afternoon.
        if clock, phrase.range(of: #"am|pm|a\.m|p\.m"#, options: .regularExpression) == nil {
            let h = Calendar.current.component(.hour, from: date)
            if (1...6).contains(h) { date = date.addingTimeInterval(12 * 3600) }
        }
        // A part of day without a time: morning 9, afternoon 2, evening 7.
        if hasTime, phrase.range(of: #"\d"#, options: .regularExpression) == nil {
            let hour = phrase.contains("morning") ? 9 : phrase.contains("afternoon") ? 14 : (phrase.contains("evening") || phrase.contains("night")) ? 19 : nil
            if let hour, !phrase.contains("noon"), !phrase.contains("midnight"), !phrase.contains(" in ") {
                date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            }
        }
        // "Friday" alone means the coming Friday, not last week's.
        if !hasTime, date < Calendar.current.startOfDay(for: Date()) { date = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date }
        return When(date: date, hasTime: hasTime, duration: duration, range: r)
    }

    /// "at 3", "at 11:30" with nothing else: the next time the clock shows it (1 to 6 means afternoon).
    private static func bareHour(in text: String) -> When? {
        guard let r = text.range(of: #"(?i)\bat (\d{1,2})(?::(\d\d))?\s*$"#, options: .regularExpression) else { return nil }
        let nums = text[r].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let hour = nums.first, (1...12).contains(hour) else { return nil }
        let cal = Calendar.current
        var h = hour == 12 ? 12 : hour < 7 ? hour + 12 : hour
        var d = cal.date(bySettingHour: h, minute: nums.count > 1 ? nums[1] : 0, second: 0, of: Date())!
        if d < Date(), h < 12 { h += 12; d = d.addingTimeInterval(12 * 3600) }
        if d < Date() { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return When(date: d, hasTime: true, duration: nil, range: r)
    }

    /// What's left of a request once the command words and the date are taken out.
    static func title(of raw: String, removing range: Range<String.Index>?) -> String {
        var s = raw
        if let range { s.replaceSubrange(range, with: " ") }
        // "create a meeting with advisor" keeps "Meeting with advisor"
        s = s.replacingOccurrences(of: #"(?i)^\s*(?:please\s+)?(?:add|schedule|create|book|make|set up)(?: an?| a new)? (meeting|appointment|call|lunch|dinner|session) (with|for) "#,
                                   with: "$1 $2 ", options: .regularExpression)
        let lead = #"^\s*(?:hey misa,?\s*)?(?:please\s+)?(?:can you\s+)?(?:remind me(?: to| about| that| of)?|(?:set|add|create|make)(?: me)? an? (?:new )?reminder(?: to| for| about| that)?|new reminder(?: to| for)?|(?:add|schedule|create|put|book|make|set up)(?: an?| a new)?(?: event| meeting| appointment| calendar event)?(?: called| named| for| to| with)?)\s*"#
        s = s.replacingOccurrences(of: lead, with: "", options: [.regularExpression, .caseInsensitive])
        let tails = [#"\s+(?:to|on|in|onto|into) (?:my|the) calendar\b"#, #"\s+on (?:my|the) schedule\b"#, #"\s+for (?:an?|one|\d+(?:\.\d+)?|half an?) (?:hours?|hrs?|minutes?|mins?)\b"#,
                     #"\s+(?:to|on|in) (?:my )?reminders\b"#]
        for p in tails { s = s.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive]) }
        // Little words left next to where the date was: "at", "on", "by", "this", trailing commas.
        for _ in 0..<3 {
            s = s.replacingOccurrences(of: #"\s+(?:at|on|by|for|from|this|next|until|till|due|starting|,)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"^\s*(?:at|on|by|for|from|this|next|to|about|that|,)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?")))
        return s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "Fri, Nov 28, 3:00 PM", or "Today" / "Tomorrow" where it reads better.
    static func describe(_ d: Date, time: Bool = true) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(d) { day = "Today" } else if cal.isDateInTomorrow(d) { day = "Tomorrow" } else {
            day = d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return time ? "\(day), \(d.formatted(date: .omitted, time: .shortened))" : day
    }

    // MARK: Creating

    static func newReminder(_ raw: String) -> Reply {
        let w = when(in: raw)
        let name = title(of: raw, removing: w?.range)
        guard !name.isEmpty else { return Reply(text: "What should I remind you about?") }
        var items = ["“\(name)”"]
        if let w { items.append(w.hasTime ? "Due \(describe(w.date))" : "Due \(describe(w.date, time: false)) (I'll nudge you at 9 AM)") } else { items.append("No due date") }
        items.append("In Reminders (synced to your iPhone through iCloud)")
        return Reply(text: "Here's the reminder:", confirm: .init(title: "Add this reminder?", items: items, button: "Add reminder", danger: false) {
            saveReminder(name, when: w)
        })
    }

    private static func saveReminder(_ name: String, when w: When?) -> Reply {
        guard allowed(.reminder) else { return noAccess(.reminder) }
        guard let list = writable(.reminder) else { return Reply(text: "You don't have a Reminders list I can add to. Make one in the Reminders app, then ask again.") }
        let r = EKReminder(eventStore: store)
        r.title = name
        r.calendar = list
        var fire: Date?
        if let w {
            let parts: Set<Calendar.Component> = w.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            r.dueDateComponents = Calendar.current.dateComponents(parts, from: w.date)
            fire = w.hasTime ? w.date : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: w.date)
        }
        do { try store.save(r, commit: true) } catch { return Reply(text: "Reminders wouldn't save it (\(error.localizedDescription)).") }
        FileOps.log("reminder added: \(name)\(w.map { " @ \($0.date)" } ?? "")")
        if let fire, fire > Date() { Notices.remind(id: r.calendarItemIdentifier, title: name, at: fire) }
        var text = "Added “\(name)” to \(list.title)"
        if let w { text += w.hasTime ? " for \(describe(w.date))" : " for \(describe(w.date, time: false).lowercased())" }
        text += "."
        if let fire, fire > Date() { text += w?.hasTime == true ? " I'll ping you then." : " I'll ping you at 9 AM that day." }
        return Reply(text: text + " ✅",
                     suggestions: [.init(label: "My reminders", prompt: "What are my reminders?")])
    }

    static func newEvent(_ raw: String) -> Reply {
        guard let w = when(in: raw) else {
            let name = title(of: raw, removing: nil)
            return Reply(text: "When is \(name.isEmpty ? "it" : "“\(name)”")?", suggestions: [
                .init(label: "Tomorrow 3 PM", prompt: "\(raw) tomorrow at 3pm"),
                .init(label: "Today 6 PM", prompt: "\(raw) today at 6pm"),
            ])
        }
        let name = title(of: raw, removing: w.range)
        guard !name.isEmpty else { return Reply(text: "What's the event called?") }
        var length = w.duration ?? 3600
        if w.duration == nil, let r = raw.range(of: #"for (?:an?|one|\d+(?:\.\d+)?|half an?) (?:hours?|hrs?|minutes?|mins?)"#, options: [.regularExpression, .caseInsensitive]) {
            length = raw[r].lowercased().contains("half") ? 1800 : (FocusTimer.parseDuration(String(raw[r]).replacingOccurrences(of: "an hour", with: "1 hour").replacingOccurrences(of: "a hour", with: "1 hour").replacingOccurrences(of: "one", with: "1")) ?? 3600)
        }
        let end = w.date.addingTimeInterval(length)
        let span = w.hasTime ? "\(describe(w.date)) – \(end.formatted(date: .omitted, time: .shortened))" : "\(describe(w.date, time: false)), all day"
        let calendarName = allowedQuietly(.event) ? (store.defaultCalendarForNewEvents?.title ?? "your calendar") : "your default calendar"
        return Reply(text: "Here's the event:", confirm: .init(title: "Add to your calendar?", items: ["“\(name)”", span, "Calendar: \(calendarName)"], button: "Add event", danger: false) {
            saveEvent(name, when: w, end: end)
        })
    }

    static func allowedQuietly(_ type: EKEntityType) -> Bool { EKEventStore.authorizationStatus(for: type) == .fullAccess }

    /// Your default calendar or list; else the first one that can be added to (reloading once if none show).
    static func writable(_ type: EKEntityType) -> EKCalendar? {
        func pick() -> EKCalendar? {
            let def = type == .event ? store.defaultCalendarForNewEvents : store.defaultCalendarForNewReminders()
            if let def, def.allowsContentModifications { return def }
            return store.calendars(for: type).first { $0.allowsContentModifications }
        }
        if let c = pick() { return c }
        store.reset()
        let c = pick()
        if c == nil { FileOps.log("agenda: no writable \(type == .event ? "calendar" : "reminder list") among \(store.calendars(for: type).count) (sources: \(store.sources.map(\.title)))") }
        return c
    }

    private static func saveEvent(_ name: String, when w: When, end: Date) -> Reply {
        guard allowed(.event) else { return noAccess(.event) }
        guard let cal = writable(.event) else { return Reply(text: "You don't have a calendar I can add to. Make one in the Calendar app, then ask again.") }
        let e = EKEvent(eventStore: store)
        e.title = name
        e.calendar = cal
        if w.hasTime {
            e.startDate = w.date
            e.endDate = end
        } else {
            e.isAllDay = true
            e.startDate = Calendar.current.startOfDay(for: w.date)
            e.endDate = e.startDate
        }
        do { try store.save(e, span: .thisEvent, commit: true) } catch { return Reply(text: "Calendar wouldn't save it (\(error.localizedDescription)).") }
        FileOps.log("event added: \(name) @ \(w.date)")
        if w.hasTime { Notices.headsUp(id: e.eventIdentifier ?? UUID().uuidString, title: name, starts: w.date) }
        let when = w.hasTime ? describe(w.date) : describe(w.date, time: false).lowercased() + " (all day)"
        return Reply(text: "Added “\(name)” to \(cal.title), \(when).\(w.hasTime && w.date.timeIntervalSinceNow > 600 ? " I'll give you a heads-up 10 minutes before." : "") 📅",
                     suggestions: [.init(label: "What's on that day?", prompt: "What's on my calendar \(Calendar.current.isDateInToday(w.date) ? "today" : Calendar.current.isDateInTomorrow(w.date) ? "tomorrow" : w.date.formatted(.dateTime.weekday(.wide)))")])
    }

    // MARK: Reading

    static func agenda(_ t: String) -> Reply {
        guard allowed(.event) else { return noAccess(.event) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var start = today, days = 1, label = "today"
        if t.contains("tomorrow") { start = cal.date(byAdding: .day, value: 1, to: today)!; label = "tomorrow" }
        else if t.contains("next week") { start = cal.date(byAdding: .day, value: 7 - cal.component(.weekday, from: today) + 1, to: today)!; days = 7; label = "next week" }
        else if t.contains("week") { days = 7; label = "this week" }
        else if let w = when(in: t), !t.contains("today") { start = cal.startOfDay(for: w.date); label = describe(w.date, time: false) }
        let end = cal.date(byAdding: .day, value: days, to: start)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        guard !events.isEmpty else { return Reply(text: "Nothing on your calendar \(label). 🎉", suggestions: [.init(label: "Add an event", prompt: "Add an event")]) }
        var lines: [String] = []
        var lastDay = ""
        for e in events.prefix(14) {
            if days > 1 {
                let d = describe(e.startDate, time: false)
                if d != lastDay { lines.append("\(d):"); lastDay = d }
            }
            let time = e.isAllDay ? "All day" : "\(e.startDate.formatted(date: .omitted, time: .shortened))–\(e.endDate.formatted(date: .omitted, time: .shortened))"
            lines.append("• \(time)  \(e.title ?? "Untitled")")
        }
        if events.count > 14 { lines.append("…and \(events.count - 14) more") }
        let free = t.hasPrefix("am i free") || t.hasPrefix("am i busy")
        let head = free ? (events.contains { !$0.isAllDay && $0.startDate <= Date() && $0.endDate > Date() } ? "You're busy right now. " : "") : ""
        return Reply(text: "\(head)\(label.prefix(1).uppercased() + label.dropFirst()):\n" + lines.joined(separator: "\n"))
    }

    static func next() -> Reply {
        guard allowed(.event) else { return noAccess(.event) }
        let now = Date()
        let soon = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(14 * 86400), calendars: nil))
            .filter { !$0.isAllDay && $0.startDate >= now.addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }
        guard let e = soon.first else { return Reply(text: "Nothing coming up in the next two weeks.") }
        let mins = Int(e.startDate.timeIntervalSince(now) / 60)
        let inText = mins < 1 ? "now" : mins < 60 ? "in \(mins) min" : mins < 24 * 60 ? "in \(FocusTimer.describe(Double(mins) * 60))" : describe(e.startDate)
        return Reply(text: "Next: \(e.title ?? "Untitled") at \(e.startDate.formatted(date: .omitted, time: .shortened)) (\(inText))\(e.location.map { ", \($0)" } ?? "").")
    }

    static func fetchIncomplete() -> [EKReminder] {
        let done = DispatchSemaphore(value: 0)
        var out: [EKReminder] = []
        store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) { r in
            out = r ?? []
            done.signal()
        }
        done.wait()
        return out
    }

    static func reminders() -> Reply {
        guard allowed(.reminder) else { return noAccess(.reminder) }
        let all = fetchIncomplete()
        guard !all.isEmpty else { return Reply(text: "No open reminders. All clear! ✨") }
        let cal = Calendar.current
        func due(_ r: EKReminder) -> Date? { r.dueDateComponents.flatMap { cal.date(from: $0) } }
        let sorted = all.sorted { (due($0) ?? .distantFuture) < (due($1) ?? .distantFuture) }
        let lines = sorted.prefix(12).map { r -> String in
            guard let d = due(r) else { return "• \(r.title ?? "Untitled")" }
            let late = d < Date() ? " ⚠️ overdue" : ""
            return "• \(r.title ?? "Untitled") (\(describe(d, time: r.dueDateComponents?.hour != nil)))\(late)"
        }
        return Reply(text: "Your reminders:\n" + lines.joined(separator: "\n") + (all.count > 12 ? "\n…and \(all.count - 12) more" : ""),
                     suggestions: sorted.prefix(2).map { .init(label: "Done: \($0.title ?? "")".prefix(28).description, prompt: "Mark \($0.title ?? "") done") })
    }

    /// Only asks Reminders when access is already granted (used to recognize "I finished X").
    private static func hasReminder(like what: String) -> Bool {
        guard allowedQuietly(.reminder) else { return false }
        return !SystemControls.best(what, fetchIncomplete()) { $0.title ?? "" }.isEmpty
    }

    static func complete(_ what: String) -> Reply {
        guard allowed(.reminder) else { return noAccess(.reminder) }
        let hits = SystemControls.best(what, fetchIncomplete()) { $0.title ?? "" }
        guard let r = hits.first else { return Reply(text: "I don't see an open reminder like “\(what)”.", suggestions: [.init(label: "My reminders", prompt: "What are my reminders?")]) }
        if hits.count > 1 { return Reply(text: "Which one?", suggestions: hits.prefix(4).map { .init(label: $0.title ?? "?", prompt: "Mark \($0.title ?? "") done") }) }
        return markDone(r)
    }

    static func complete(id: String) {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess, let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        _ = markDone(r)
    }

    private static func markDone(_ r: EKReminder) -> Reply {
        r.isCompleted = true
        do { try store.save(r, commit: true) } catch { return Reply(text: "Reminders wouldn't save that (\(error.localizedDescription)).") }
        Notices.cancel(r.calendarItemIdentifier)
        FileOps.log("reminder done: \(r.title ?? "")")
        return Reply(text: "Checked off “\(r.title ?? "")”. Nice! ✅")
    }
}

/// M.I.S.A.'s own notifications for reminders and events she made (delivered by macOS even
/// when she isn't running). Reminders get Done and Snooze buttons.
enum Notices {
    static let reminderCategory = "misa.reminder"
    static let done = "misa.done"
    static let snooze = "misa.snooze"

    /// Called at launch so the buttons exist.
    static func register() {
        let category = UNNotificationCategory(identifier: reminderCategory, actions: [
            UNNotificationAction(identifier: done, title: "Done", options: []),
            UNNotificationAction(identifier: snooze, title: "Snooze 10 min", options: []),
        ], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func remind(id: String, title: String, at date: Date) {
        schedule(id: "rem.\(id)", title: "⏰ \(title)", body: "Reminder from M.I.S.A.", at: date, category: reminderCategory, info: ["reminder": id, "title": title])
    }

    static func headsUp(id: String, title: String, starts: Date) {
        let at = starts.addingTimeInterval(-600)
        guard at > Date() else { return }
        schedule(id: "evt.\(id)", title: "📅 \(title)", body: "Starts at \(starts.formatted(date: .omitted, time: .shortened)), in 10 minutes.", at: at, category: nil, info: [:])
    }

    static func cancelEvent(_ eventID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["evt.\(eventID)"])
    }

    static func cancel(_ reminderID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rem.\(reminderID)"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["rem.\(reminderID)"])
    }

    /// The buttons on a reminder banner.
    static func handle(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        guard let id = info["reminder"] as? String else { return }
        switch response.actionIdentifier {
        case done:
            DispatchQueue.global().async { Agenda.complete(id: id) }
        case snooze:
            remind(id: id, title: info["title"] as? String ?? "Reminder", at: Date().addingTimeInterval(600))
        default:
            break
        }
    }

    private static func schedule(id: String, title: String, body: String, at date: Date, category: String?, info: [String: String]) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return FileOps.log("notifications not allowed; \(title) won't ping") }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = info
            if let category { content.categoryIdentifier = category }
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))) { error in
                if let error { FileOps.log("notice failed: \(error.localizedDescription)") }
            }
        }
    }
}
