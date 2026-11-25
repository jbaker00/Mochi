import Cocoa
import EventKit

// MARK: - Mail (reads Mail.app, so it covers Gmail, Outlook, iCloud… whatever is added there)

struct MailItem {
    let account: String
    let id: String
    let sender: String
    let subject: String
}

final class MailWatcher {
    var filter: [String]
    var onNew: (([MailItem]) -> Void)?
    var onProblem: ((String) -> Void)?

    private(set) var unreadByAccount: [String: Int] = [:]
    private(set) var hasData = false

    private let queue = DispatchQueue(label: "mochi.mail")
    private var seen = Set<String>()
    private var primed = false
    private var busy = false
    private var warnedNotRunning = false
    private var warnedPermission = false

    init(filter: [String]) {
        self.filter = filter.map { $0.lowercased() }
    }

    // Fields separated by ASCII 31, records by ASCII 30.
    private static let script = """
    set US to character id 31
    set RS to character id 30
    set out to ""
    tell application "Mail"
        repeat with acct in accounts
            try
                if enabled of acct then
                    set acctName to name of acct
                    set addrs to ""
                    try
                        set AppleScript's text item delimiters to ","
                        set addrs to (email addresses of acct) as text
                        set AppleScript's text item delimiters to ""
                    end try
                    set mb to missing value
                    try
                        set mb to mailbox "INBOX" of acct
                    end try
                    if mb is missing value then
                        try
                            set mb to mailbox "Inbox" of acct
                        end try
                    end if
                    if mb is not missing value then
                        set n to unread count of mb
                        set out to out & "A" & US & acctName & US & addrs & US & n & RS
                        if n > 0 then
                            set unreadMsgs to (messages of mb whose read status is false)
                            set lim to count of unreadMsgs
                            if lim > 15 then set lim to 15
                            repeat with i from 1 to lim
                                try
                                    set m to item i of unreadMsgs
                                    set mid to ""
                                    try
                                        set mid to message id of m
                                    end try
                                    set snd to ""
                                    try
                                        set snd to sender of m
                                    end try
                                    set subj to "(no subject)"
                                    try
                                        set subj to subject of m
                                    end try
                                    if mid is "" then set mid to acctName & snd & subj
                                    set out to out & "M" & US & acctName & US & mid & US & snd & US & subj & RS
                                end try
                            end repeat
                        end if
                    end if
                end if
            end try
        end repeat
    end tell
    return out
    """

    var isMailRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
    }

    func poll() {
        guard !busy else { return }
        guard isMailRunning else {
            if !warnedNotRunning {
                warnedNotRunning = true
                onProblem?("Open the Mail app and I'll watch your Gmail & Outlook inboxes for you!")
            }
            return
        }
        warnedNotRunning = false
        busy = true
        queue.async { [weak self] in
            var err: NSDictionary?
            let result = NSAppleScript(source: MailWatcher.script)?.executeAndReturnError(&err)
            let text = result?.stringValue
            let code = (err?[NSAppleScript.errorNumber] as? Int) ?? 0
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                if let text = text {
                    self.process(text)
                } else if code == -1743 || code == -1744 {
                    if !self.warnedPermission {
                        self.warnedPermission = true
                        self.onProblem?("I need permission to peek at Mail. System Settings › Privacy & Security › Automation › Mochi › turn on Mail.")
                    }
                }
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        if filter.isEmpty { return true }
        let t = text.lowercased()
        return filter.contains { t.contains($0) }
    }

    private func process(_ text: String) {
        let US = "\u{1F}", RS = "\u{1E}"
        var counts: [String: Int] = [:]
        var allowed = Set<String>()
        var items: [MailItem] = []
        for rec in text.components(separatedBy: RS) where !rec.isEmpty {
            let f = rec.components(separatedBy: US)
            if f.first == "A", f.count >= 4 {
                if matches(f[1] + " " + f[2]) {
                    allowed.insert(f[1])
                    counts[f[1]] = Int(f[3].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            } else if f.first == "M", f.count >= 5 {
                items.append(MailItem(account: f[1], id: f[1] + "|" + f[2],
                                      sender: MailWatcher.cleanSender(f[3]), subject: f[4]))
            }
        }
        items = items.filter { allowed.contains($0.account) }
        unreadByAccount = counts
        hasData = true
        warnedPermission = false

        let fresh = items.filter { !seen.contains($0.id) }
        items.forEach { seen.insert($0.id) }
        if !primed { primed = true; return }   // don't alert for mail that was already waiting at launch
        if !fresh.isEmpty { onNew?(fresh) }
    }

    static func cleanSender(_ s: String) -> String {
        var name = s
        if let lt = s.firstIndex(of: "<") {
            name = String(s[..<lt]).trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                name = String(s[s.index(after: lt)...]).replacingOccurrences(of: ">", with: "")
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return name.isEmpty ? "Someone" : name
    }
}

// MARK: - Calendar (EventKit, so every calendar in Calendar.app: iCloud, Google, Outlook/Exchange…)

final class CalendarWatcher {
    let store = EKEventStore()
    var leadMinutes: [Int]
    var useAlarms: Bool
    var dayStartHour: Int
    private(set) var authorized = false

    private var cache: [EKEvent] = []
    private var lastRefresh = Date.distantPast
    private var fired = Set<String>()

    init(leadMinutes: [Int], useAlarms: Bool, dayStartHour: Int) {
        self.leadMinutes = leadMinutes
        self.useAlarms = useAlarms
        self.dayStartHour = dayStartHour
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.lastRefresh = .distantPast
        }
    }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                self?.lastRefresh = .distantPast
                done(granted)
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    private func refreshIfNeeded(_ now: Date) {
        guard authorized, now.timeIntervalSince(lastRefresh) > 300 else { return }
        lastRefresh = now
        let start = Calendar.current.startOfDay(for: now)
        let end = now.addingTimeInterval(36 * 3600)
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        cache = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
    }

    /// Next timed events that haven't started yet (within 24h).
    func upcoming(_ limit: Int, now: Date = Date()) -> [EKEvent] {
        refreshIfNeeded(now)
        return Array(cache.filter { !$0.isAllDay && $0.startDate > now && $0.startDate < now.addingTimeInterval(24 * 3600) }.prefix(limit))
    }

    func check(now: Date = Date()) -> [BubbleMessage] {
        refreshIfNeeded(now)
        guard authorized else { return [] }
        var out: [BubbleMessage] = []
        var allDay: [EKEvent] = []
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let day = cal.dateComponents([.year, .month, .day], from: now)
        let dayKey = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"

        for ev in cache {
            guard let start = ev.startDate else { continue }
            let id = ev.calendarItemIdentifier + "|" + String(Int(start.timeIntervalSince1970))

            if ev.isAllDay {
                let end = ev.endDate ?? start
                guard start <= now, end > now, hour >= dayStartHour else { continue }
                if fired.insert("allday|" + id + "|" + dayKey).inserted { allDay.append(ev) }
                continue
            }

            var offsets = Set(leadMinutes.filter { $0 > 0 })
            if useAlarms, let alarms = ev.alarms {
                for a in alarms where a.absoluteDate == nil && a.relativeOffset < 0 {
                    offsets.insert(Int((-a.relativeOffset / 60).rounded()))
                }
            }
            offsets.insert(0)

            let due = offsets.filter { now >= start.addingTimeInterval(-Double($0) * 60) }
            guard !due.isEmpty else { continue }
            let newlyDue = due.filter { !fired.contains(id + "|" + String($0)) }
            guard !newlyDue.isEmpty else { continue }
            due.forEach { fired.insert(id + "|" + String($0)) }
            if now > start.addingTimeInterval(120) { continue }   // already well under way

            let mins = Int(ceil(start.timeIntervalSince(now) / 60))
            out.append(message(for: ev, minutesAway: mins))
        }

        if !allDay.isEmpty {
            let names = allDay.prefix(4).map { "• " + ($0.title ?? "Event") }.joined(separator: "\n")
            out.append(BubbleMessage(kind: .calendar, title: "🌤️ Today", body: names,
                                     hint: "Click to open Calendar", duration: 15, action: Apps.openCalendar))
        }
        return out
    }

    private func message(for ev: EKEvent, minutesAway mins: Int) -> BubbleMessage {
        let title = (ev.title?.isEmpty == false) ? ev.title! : "Event"
        var lines = [title]
        var detail = timeFormatter.string(from: ev.startDate)
        if let c = ev.calendar?.title { detail += " · " + c }
        lines.append(detail)
        if let loc = ev.location, !loc.isEmpty, !loc.lowercased().hasPrefix("http") { lines.append("📍 " + loc) }

        let when: String
        switch mins {
        case ..<1: when = "📅 Starting now!"
        case 1: when = "📅 In 1 minute"
        case 2..<60: when = "📅 In \(mins) minutes"
        default:
            let h = mins / 60, m = mins % 60
            when = m == 0 ? "📅 In \(h) hr" : "📅 In \(h) hr \(m) min"
        }

        let link = CalendarWatcher.meetingLink(in: ev)
        let action: () -> Void = {
            if let link = link { NSWorkspace.shared.open(link) } else { Apps.openCalendar() }
        }
        return BubbleMessage(kind: .calendar, title: when, body: lines.joined(separator: "\n"),
                             hint: link != nil ? "Click to join the meeting" : "Click to open Calendar",
                             duration: mins <= 0 ? 30 : 18, action: action)
    }

    static func meetingLink(in ev: EKEvent) -> URL? {
        var haystack = [ev.location ?? "", ev.notes ?? ""]
        if let u = ev.url { haystack.insert(u.absoluteString, at: 0) }
        let pattern = "https?://[^\\s<>\"]*(zoom\\.us|meet\\.google\\.com|teams\\.microsoft\\.com|teams\\.live\\.com|webex\\.com|facetime\\.apple\\.com)[^\\s<>\"]*"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        for text in haystack where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            if let m = re.firstMatch(in: text, range: range), let r = Range(m.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }
}
