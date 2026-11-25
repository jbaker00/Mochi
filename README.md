# Mochi 🌱 — a desktop pet for your Mac

A little cream-puff creature with a sprout on its head that wanders along the
bottom of your screen (just above the Dock). It pops up a speech bubble when new
Gmail or Outlook mail arrives and reminds you before events on any of your calendars.

## Build & run

```bash
cd Mochi
./build.sh
```

Or open `Mochi.xcodeproj` in Xcode and hit ▶︎ Run.

`build.sh` builds the Release app with `xcodebuild`, installs it to
`~/Applications`, and launches it. A 🐾 appears in the menu bar.

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`, then `xcodegen`).
The generated project is checked in, so you only need XcodeGen when you add or remove files.

### App icon

The icon is drawn by Mochi's own `PetView` code. To regenerate it:

```bash
swiftc scripts/IconGen/main.swift Sources/PetView.swift Sources/Models.swift -o /tmp/icongen
/tmp/icongen Resources/Assets.xcassets/AppIcon.appiconset
```

## First launch: two permission prompts

1. **Calendars**: click Allow. Mochi reads every calendar in Calendar.app
   (iCloud, Google, Outlook/Exchange).
2. **Mail (Automation)**: the first time it checks mail, macOS asks whether
   Mochi can control Mail. Click OK.

Missed one? Go to System Settings › Privacy & Security › Calendars / Automation.

## Where the data comes from

- **Mail** is read from **Mail.app**, so your Gmail and Outlook accounts need
  to be added there (System Settings › Internet Accounts) and Mail needs to be
  running. No passwords or OAuth are stored in Mochi.
- **Calendars** come from **Calendar.app** via EventKit.

## What it does

| Thing | Behaviour |
|---|---|
| New mail | Hops, plays "Pop", bubble with sender + subject. Click to open Mail |
| Calendar | Reminds 10 min before (plus each event's own alert times) and at start. Click to join a Zoom/Meet/Teams link if there is one, otherwise opens Calendar |
| All-day events | One "Today" bubble each morning |
| Click Mochi | Hearts + a random funny saying (edit them in `Sources/FunnySayings.swift`) |
| 🐾 › Mail & calendar summary | Unread count and your next event |
| Night (11pm–7am) | Naps with floating z's |
| Hover a bubble | Keeps it open |

Clicks pass straight through everywhere except Mochi and its bubble.

## Settings

Menu bar 🐾 › **Edit settings…** opens
`~/Library/Application Support/Mochi/config.json`. Edit it, then click **Reload settings**.

- `mailAccountFilter`: words matched against each Mail account's name and
  address. The default is Gmail + Outlook only. Set it to `[]` to include iCloud too.
- `calendarLeadMinutes`: for example `[15, 5]`
- `walkSpeed`, `bubbleSeconds`, `playSound`, `sleepStartHour`, `sleepEndHour`, `petName`

The 🐾 menu also has *Stay put*, *Hide pet*, *Open at login*, and test bubbles.

> Each rebuild is ad-hoc signed with a new signature, so macOS may ask for permissions again after a rebuild.
