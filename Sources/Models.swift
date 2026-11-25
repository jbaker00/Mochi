import Cocoa

// MARK: - Colors

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Bubble messages

enum BubbleKind {
    case mail, calendar, info
}

struct BubbleMessage {
    var kind: BubbleKind
    var title: String
    var body: String
    var hint: String? = nil
    var duration: Double = 10
    var action: (() -> Void)? = nil
}

// MARK: - Config (~/Library/Application Support/Mochi/config.json)

struct PetConfig {
    var petName = "Mochi"
    /// How often to check Mail.app, in seconds.
    var mailPollSeconds: Double = 45
    /// Only alert for Mail accounts whose name or address contains one of these words.
    /// Set to [] to alert for every account (iCloud included).
    var mailAccountFilter: [String] = ["gmail", "google", "outlook", "hotmail", "live", "msn", "exchange", "office", "microsoft"]
    /// Minutes before an event to remind you (a "starting now" reminder is always added).
    var calendarLeadMinutes: [Int] = [10]
    /// Also remind at the alert times set on each event in Calendar.
    var useEventAlarms = true
    /// Walking speed in points per second.
    var walkSpeed: Double = 34
    /// How long a bubble stays up (seconds). Hovering the bubble pauses the countdown.
    var bubbleSeconds: Double = 12
    var playSound = true
    /// Mochi naps between these hours (24h clock).
    var sleepStartHour = 23
    var sleepEndHour = 7

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mochi", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> PetConfig {
        var c = PetConfig()
        guard let data = try? Data(contentsOf: fileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            c.save()
            return c
        }
        if let v = obj["petName"] as? String, !v.isEmpty { c.petName = v }
        if let v = obj["mailPollSeconds"] as? Double { c.mailPollSeconds = max(15, v) }
        if let v = obj["mailAccountFilter"] as? [String] { c.mailAccountFilter = v }
        if let v = obj["calendarLeadMinutes"] as? [Int] { c.calendarLeadMinutes = v }
        if let v = obj["useEventAlarms"] as? Bool { c.useEventAlarms = v }
        if let v = obj["walkSpeed"] as? Double { c.walkSpeed = min(200, max(5, v)) }
        if let v = obj["bubbleSeconds"] as? Double { c.bubbleSeconds = max(3, v) }
        if let v = obj["playSound"] as? Bool { c.playSound = v }
        if let v = obj["sleepStartHour"] as? Int { c.sleepStartHour = v }
        if let v = obj["sleepEndHour"] as? Int { c.sleepEndHour = v }
        return c
    }

    func save() {
        let dict: [String: Any] = [
            "petName": petName,
            "mailPollSeconds": mailPollSeconds,
            "mailAccountFilter": mailAccountFilter,
            "calendarLeadMinutes": calendarLeadMinutes,
            "useEventAlarms": useEventAlarms,
            "walkSpeed": walkSpeed,
            "bubbleSeconds": bubbleSeconds,
            "playSound": playSound,
            "sleepStartHour": sleepStartHour,
            "sleepEndHour": sleepEndHour,
        ]
        try? FileManager.default.createDirectory(at: PetConfig.directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: PetConfig.fileURL)
        }
    }

    func isSleepTime(_ date: Date = Date()) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        if sleepStartHour == sleepEndHour { return false }
        if sleepStartHour > sleepEndHour { return h >= sleepStartHour || h < sleepEndHour }
        return h >= sleepStartHour && h < sleepEndHour
    }
}

// MARK: - Helpers

enum Apps {
    static func open(bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    static func openMail() { open(bundleID: "com.apple.mail") }
    static func openCalendar() { open(bundleID: "com.apple.iCal") }
}

let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
}()
