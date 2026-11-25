import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = PetConfig.load()
    private var window: NSPanel!
    private var petView: PetView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private var mail: MailWatcher!
    private var calendar: CalendarWatcher!

    private let W: CGFloat = 340
    private let H: CGFloat = 240

    private var petX: CGFloat = 0
    private var lastTick = CACurrentMediaTime()
    private var moodTimer: CGFloat = 3
    private var stayPut = false
    private var hidden = false

    private var queue: [BubbleMessage] = []
    private var bubbleRemaining: Double = 0
    private var lastMailPoll = Date.distantPast
    private var lastCalendarCheck = Date.distantPast

    private var stayItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var hideItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        mail = MailWatcher(filter: config.mailAccountFilter)
        calendar = CalendarWatcher(leadMinutes: config.calendarLeadMinutes,
                                   useAlarms: config.useEventAlarms,
                                   dayStartHour: config.sleepEndHour)

        buildWindow()
        buildStatusItem()
        wireCallbacks()

        let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(self, selector: #selector(clampToScreen),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        show(BubbleMessage(kind: .info, title: "Hi! I'm \(config.petName) 🌱",
                           body: "I'll pop up when new Gmail or Outlook mail lands, and remind you before calendar events.",
                           hint: "Tap me for a laugh", duration: 9))

        calendar.requestAccess { [weak self] granted in
            guard let self = self else { return }
            if !granted {
                self.show(BubbleMessage(kind: .info, title: "📅 Can I see your calendars?",
                                        body: "Turn on Mochi in System Settings › Privacy & Security › Calendars so I can remind you about events.",
                                        hint: "Click to open Settings", duration: 20,
                                        action: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }))
            }
        }
        // first mail check shortly after launch (this is what triggers the Automation prompt)
        lastMailPoll = Date().addingTimeInterval(-config.mailPollSeconds + 4)
    }

    // MARK: Setup

    private func screen() -> NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    private func buildWindow() {
        let vf = screen()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        petX = vf.midX
        window = NSPanel(contentRect: NSRect(x: petX - W / 2, y: vf.minY, width: W, height: H),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        petView = PetView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        window.contentView = petView
        window.orderFrontRegardless()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        let menu = NSMenu()
        menu.addItem(item("Mail & calendar summary", #selector(sayHi)))
        menu.addItem(item("Upcoming events", #selector(showUpcoming)))
        menu.addItem(item("Check mail now", #selector(checkMailNow)))
        menu.addItem(.separator())
        stayItem = item("Stay put (don’t walk)", #selector(toggleStay))
        menu.addItem(stayItem)
        hideItem = item("Hide pet", #selector(toggleHidden))
        menu.addItem(hideItem)
        loginItem = item("Open at login", #selector(toggleLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Test mail bubble", #selector(testMail)))
        menu.addItem(item("Test calendar bubble", #selector(testCalendar)))
        menu.addItem(item("Edit settings…", #selector(openConfig)))
        menu.addItem(item("Reload settings", #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(config.petName)", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    private func wireCallbacks() {
        petView.onPetClick = { [weak self] in self?.petClicked() }
        petView.onBubbleClick = { [weak self] in
            guard let self = self else { return }
            let action = self.petView.bubble?.action
            self.petView.closeBubble()
            action?()
        }
        petView.onBubbleGone = { [weak self] in
            guard let self = self, !self.queue.isEmpty else { return }
            self.present(self.queue.removeFirst())
        }
        mail.onNew = { [weak self] items in self?.announceMail(items) }
        mail.onProblem = { [weak self] text in
            self?.show(BubbleMessage(kind: .info, title: "✉️ Psst…", body: text, duration: 14))
        }
    }

    // MARK: Loop

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.1, now - lastTick))
        lastTick = now
        guard let scr = screen() else { return }
        let vf = scr.visibleFrame

        updateBehavior(dt, minX: vf.minX + 55, maxX: vf.maxX - 55)
        petView.update(dt: dt)

        let origin = NSPoint(x: petX - W / 2, y: vf.minY)
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
        petView.visibleRange = (scr.frame.minX - origin.x)...(scr.frame.maxX - origin.x)

        // let clicks pass through everywhere except Mochi and its bubble
        let m = NSEvent.mouseLocation
        let local = NSPoint(x: m.x - origin.x, y: m.y - origin.y)
        let overBubble = petView.bubble != nil && petView.bubbleRect.contains(local)
        let interactive = !hidden && (petView.petRect.contains(local) || overBubble)
        if window.ignoresMouseEvents == interactive { window.ignoresMouseEvents = !interactive }

        if petView.bubble != nil && !overBubble {
            bubbleRemaining -= Double(dt)
            if bubbleRemaining <= 0 { petView.closeBubble() }
        }
        petView.needsDisplay = true

        let date = Date()
        if date.timeIntervalSince(lastMailPoll) >= config.mailPollSeconds {
            lastMailPoll = date
            mail.poll()
        }
        if date.timeIntervalSince(lastCalendarCheck) >= 15 {
            lastCalendarCheck = date
            calendar.check(now: date).forEach { show($0) }
        }
    }

    private func updateBehavior(_ dt: CGFloat, minX: CGFloat, maxX: CGFloat) {
        petX = min(max(petX, minX), maxX)
        moodTimer -= dt
        let sleepy = config.isSleepTime()

        switch petView.mood {
        case .walking:
            if stayPut { setMood(.idle); break }
            let dir: CGFloat = petView.facingRight ? 1 : -1
            petX += dir * CGFloat(config.walkSpeed) * dt
            petView.walkPhase += dt * 9
            if petX >= maxX { petX = maxX; petView.facingRight = false }
            if petX <= minX { petX = minX; petView.facingRight = true }
            if moodTimer <= 0 { setMood(Bool.random() ? .idle : .sitting) }
        case .idle, .sitting:
            if moodTimer <= 0 {
                if sleepy && Double.random(in: 0...1) < 0.6 { setMood(.sleeping) }
                else if stayPut { setMood(Bool.random() ? .idle : .sitting) }
                else { setMood(.walking) }
            }
        case .sleeping:
            if moodTimer <= 0 { if sleepy { moodTimer = 60 } else { setMood(.idle) } }
        case .excited:
            if moodTimer <= 0 { setMood(.idle) }
        }
    }

    private func setMood(_ m: PetView.Mood) {
        petView.mood = m
        switch m {
        case .walking:
            moodTimer = CGFloat.random(in: 4...11)
            if Double.random(in: 0...1) < 0.4 { petView.facingRight.toggle() }
        case .idle: moodTimer = CGFloat.random(in: 2...5)
        case .sitting: moodTimer = CGFloat.random(in: 4...9)
        case .sleeping: moodTimer = CGFloat.random(in: 40...90)
        case .excited: moodTimer = 2.5
        }
    }

    @objc private func clampToScreen() {
        guard let vf = screen()?.visibleFrame else { return }
        petX = min(max(petX, vf.minX + 55), vf.maxX - 55)
    }

    // MARK: Bubbles

    private func show(_ m: BubbleMessage) {
        if petView.bubble == nil { present(m) } else { queue.append(m) }
    }

    private func present(_ m: BubbleMessage) {
        petView.showBubble(m)
        bubbleRemaining = m.kind == .mail ? max(config.bubbleSeconds, m.duration) : m.duration
        if m.kind != .info {
            setMood(.excited)
            petView.hop()
            if config.playSound {
                NSSound(named: NSSound.Name(m.kind == .mail ? "Pop" : "Glass"))?.play()
            }
        } else if petView.mood == .sleeping {
            setMood(.idle)
        }
    }

    private func announceMail(_ items: [MailItem]) {
        if items.count == 1, let i = items.first {
            show(BubbleMessage(kind: .mail, title: "✉️ New mail · \(i.account)",
                               body: "\(i.sender)\n\(i.subject)",
                               hint: "Click to open Mail", duration: config.bubbleSeconds, action: Apps.openMail))
        } else {
            let lines = items.prefix(3).map { "• \($0.sender): \($0.subject)" }
            let more = items.count > 3 ? "\n…and \(items.count - 3) more" : ""
            show(BubbleMessage(kind: .mail, title: "✉️ \(items.count) new emails!",
                               body: lines.joined(separator: "\n") + more,
                               hint: "Click to open Mail", duration: config.bubbleSeconds + 4, action: Apps.openMail))
        }
    }

    private var lastSaying: String?

    /// Tapping Mochi: a hop, some hearts, and a silly one-liner.
    private func petClicked() {
        petView.pet()
        if petView.mood == .sleeping { setMood(.idle) }
        guard petView.bubble == nil else { return }
        var saying = FunnySayings.all.randomElement()!
        while saying == lastSaying { saying = FunnySayings.all.randomElement()! }
        lastSaying = saying
        show(BubbleMessage(kind: .info, title: "\(config.petName) says…", body: saying, duration: 7))
    }

    /// Unread mail counts + next event (menu bar › Say hi).
    private func showSummary() {
        petView.pet()
        if petView.mood == .sleeping { setMood(.idle) }

        var lines: [String] = []
        if mail.hasData {
            let counts = mail.unreadByAccount.filter { $0.value > 0 }
            let total = counts.values.reduce(0, +)
            if total == 0 {
                lines.append("📭 Inbox zero — nice!")
            } else {
                let detail = counts.count > 1
                    ? " (" + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")"
                    : ""
                lines.append("📬 \(total) unread\(detail)")
            }
        } else if !mail.isMailRunning {
            lines.append("📬 Open Mail so I can watch your inbox")
        } else {
            lines.append("📬 Checking your mail…")
        }
        if calendar.authorized {
            if let next = calendar.upcoming(1).first {
                lines.append("📅 Next: \(next.title ?? "Event") at \(timeFormatter.string(from: next.startDate))")
            } else {
                lines.append("📅 Nothing else on the calendar")
            }
        }
        let hellos = ["Hi hi! 👋", "*happy wiggle*", "You’re doing great! ✨", "Snack break? 🍡"]
        show(BubbleMessage(kind: .info, title: hellos.randomElement()!, body: lines.joined(separator: "\n"), duration: 7))
    }

    // MARK: Menu actions

    @objc private func sayHi() { if hidden { toggleHidden() }; showSummary() }

    @objc private func showUpcoming() {
        if hidden { toggleHidden() }
        guard calendar.authorized else {
            show(BubbleMessage(kind: .info, title: "📅 No calendar access yet",
                               body: "Allow Mochi in System Settings › Privacy & Security › Calendars.", duration: 10))
            return
        }
        let evs = calendar.upcoming(4)
        let body = evs.isEmpty ? "Nothing coming up in the next 24 hours 🎉"
            : evs.map { "\(timeFormatter.string(from: $0.startDate))  \($0.title ?? "Event")" }.joined(separator: "\n")
        show(BubbleMessage(kind: .calendar, title: "📅 Coming up", body: body,
                           hint: "Click to open Calendar", duration: 14, action: Apps.openCalendar))
    }

    @objc private func checkMailNow() {
        lastMailPoll = .distantPast
    }

    @objc private func toggleStay() {
        stayPut.toggle()
        stayItem.state = stayPut ? .on : .off
    }

    @objc private func toggleHidden() {
        hidden.toggle()
        hideItem.state = hidden ? .on : .off
        if hidden { window.orderOut(nil) } else { window.orderFrontRegardless() }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            show(BubbleMessage(kind: .info, title: "Couldn’t change login item",
                               body: "Move Mochi.app into Applications first, then try again. (\(error.localizedDescription))",
                               duration: 12))
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func testMail() {
        announceMail([MailItem(account: "Gmail", id: UUID().uuidString, sender: "Mochi Test",
                               subject: "This is what a new email looks like ✨")])
    }

    @objc private func testCalendar() {
        show(BubbleMessage(kind: .calendar, title: "📅 In 10 minutes",
                           body: "Sample meeting\n\(timeFormatter.string(from: Date().addingTimeInterval(600))) · Calendar",
                           hint: "Click to open Calendar", duration: 12, action: Apps.openCalendar))
    }

    @objc private func openConfig() {
        config.save()   // make sure the file exists with every key
        NSWorkspace.shared.open(PetConfig.fileURL)
    }

    @objc private func reloadConfig() {
        config = PetConfig.load()
        mail.filter = config.mailAccountFilter.map { $0.lowercased() }
        calendar.leadMinutes = config.calendarLeadMinutes
        calendar.useAlarms = config.useEventAlarms
        calendar.dayStartHour = config.sleepEndHour
        show(BubbleMessage(kind: .info, title: "Settings reloaded 👍", body: "", duration: 4))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
