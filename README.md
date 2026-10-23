# DeskDash

A personal macOS desktop command centre: **Apple Reminders** on the left, **Apple Calendar** on the right. It runs either pinned to the desktop behind every app window (Desktop mode) or as a normal resizable window.

Native Swift 6 / SwiftUI, with AppKit for window control. Everything goes through Apple's EventKit, so there is **no network code, no accounts, no backend and no analytics**. iCloud does the syncing.

| | |
|---|---|
| Platform | macOS 14+ (built and checked on macOS 27.0.1, Xcode 26.6) |
| Reminders | Two-way: add, edit (title, notes, date, optional time, priority), complete/uncomplete. No delete |
| Calendar | Add and edit events (title, all-day, start/end, repeat, location, notes, calendar). No delete. Every calendar macOS Calendar has, including iCloud and accounts synced from iPhone |
| Sync to iPhone/iPad | Automatic via iCloud. DeskDash writes to the Mac's Reminders store and iCloud carries it |
| Storage | No data of its own; just preferences in UserDefaults |

Originally specified with Google Tasks (*Technical Build Specification v1.0*, 18 Oct 2026). Replaced with Apple Reminders on 19 Oct 2026 at the owner's request.

## Build and run

```bash
brew install xcodegen
```

```bash
cd ~/Projects/DeskDash && xcodegen generate && open DeskDash.xcodeproj
```

Then press Run in Xcode. Or build from the command line:

```bash
xcodebuild -project DeskDash.xcodeproj -scheme DeskDash -derivedDataPath build build && open build/Build/Products/Debug/DeskDash.app
```

The project file is generated from `project.yml`; edit that, not the `.xcodeproj`. Signing uses your Apple Development team (`Y9T5MPV87F`).

### Demo mode (sample data)

```bash
open build/Build/Products/Debug/DeskDash.app --args -DemoMode YES
```

Demo mode uses in-memory reminders and events and a separate preferences domain, so it never touches your real Reminders or Calendar.

### Tests

```bash
xcodebuild -project DeskDash.xcodeproj -scheme DeskDash -derivedDataPath build test
```

33 unit tests. They cover all-day dates across time zones, DST days, month grids, all-day and overnight events, reminder due dates and EventKit date components, priority mapping, grouping (including timed reminders becoming overdue), and the reminders store. The store tests cover optimistic writes, rollback and retry, ordered writes, field-level edits that don't clobber changes from another device, create placeholders, read-only lists, deleted-elsewhere, and reloading on external change.

## First launch

1. Click **Allow Calendar Access…**. DeskDash uses full access to show, add and edit events. It never deletes them.
2. Click **Allow Reminders Access…**. DeskDash needs full access to add, edit and complete reminders. It never deletes them.

Both can be changed later in **System Settings → Privacy & Security → Calendars / Reminders**.

## Syncing with iPhone and iPad

DeskDash doesn't sync anything itself. It edits the Reminders data on this Mac, and iCloud syncs that to your other devices, usually within seconds. For that to work:

- Turn on **Reminders** (and **Calendars**) in **System Settings → Apple Account → iCloud** on the Mac, and in **Settings → [your name] → iCloud** on iPhone and iPad, all signed in to the same Apple Account.
- Lists under **On My Mac** stay on this Mac. Exchange or other accounts sync through their own servers.
- Changes made on your phone appear on the dashboard as soon as macOS receives them, with no polling.

## Using it

| Action | How |
|---|---|
| New reminder | ⌘N, or type in the add field and press Return (Escape cancels). The calendar icon sets an optional date or time |
| Complete / reopen | Click the circle |
| Edit | Click a reminder: title, notes, date, time, priority, then **Save**. Nothing is written while you type |
| Choose list | Click **All Lists** under the title. New reminders go to the selected list, or your default Reminders list when showing all |
| Calendar | Day / Month toggle, ‹ › to move, **Today** (⌘T). ⌘1 Day view, ⌘2 Month view, ⌘[ / ⌘] previous/next |
| New event | **+** in the calendar header, ⇧⌘E, right-click a day → New Event on This Day, or **Add Event** on an empty day |
| Edit event | Click an event → **Edit…** (⌘E). Repeating events ask: this event only, or this and future events |
| Repeat | In the editor: Never, Every Day / Week / 2 Weeks / Month / Year, ending never or on a date. Changing a repeat applies to this and future events. Existing custom patterns (weekdays only, "2nd Tuesday"…) show as **Custom** and are kept as they are |
| Refresh | ⌘R (rarely needed; changes arrive automatically) |
| Desktop ↔ window | **Send to Desktop** / **Bring to Front** button next to Settings (always visible), ⇧⌘D, or the menu-bar icon |
| Rescue | **Return to Normal Window**: ⌥⌘N, or from the menu-bar icon |
| Settings | ⌘, |

Sections: **Overdue · Today · Upcoming** (next 7 days) **· Later · No due date**, plus an optional **Completed** section (last 14 days) under the filter menu. A reminder due today at a time that has passed counts as overdue, as in the Reminders app. Rows show priority (`!!!` `!!` `!`), a repeat icon, and the list's colour when showing all lists.

Like the Reminders app, setting a **time** on a reminder adds an alert at that time, so your iPhone notifies you. Date-only reminders follow your device's all-day notification setting. Completing a **repeating** reminder moves it to its next date, which EventKit handles.

Not available through EventKit, so not shown: tags, sections, subtasks, flags and smart lists. They stay intact in the Reminders app.

## Desktop mode

Desktop mode is a borderless window placed just **above Finder's desktop-icon layer** and below every normal app window. It appears on all Spaces, stays put during Mission Control, and is skipped by ⌘\`. It is a real window, not a wallpaper image, so clicks and typing work when nothing covers it. It covers your desktop icons.

**Desktop appearance** (Settings → General), all live:

- **Transparency**: Solid ↔ Clear (default 70% clear). Only backgrounds fade; text stays fully opaque, and gets a soft outline when panels are very clear so it reads on any wallpaper.
- **Blur the wallpaper behind panels**: frosted look. Unavailable while macOS **Reduce transparency** is on (System Settings → Accessibility → Display), because that turns every system blur solid grey; DeskDash then uses a plain see-through tint instead.
- **Show buttons only when the pointer is over the dashboard**: refresh, mode, settings, calendar navigation and the add field fade out when you're not using them. ⌘N still brings up the add field.

**Settings → General → Desktop layer → Behind desktop icons** puts it under the icons instead. Icons then stay visible, but Finder takes the clicks, so the dashboard becomes display-only. See [docs/M0-window-spike.md](docs/M0-window-spike.md).

Only public AppKit/CoreGraphics APIs are used. DeskDash never asks for Accessibility or Screen Recording permission.

## Architecture

```
SwiftUI views ─▶ stores (@Observable, MainActor) ─▶ repository protocols ─▶ EventKit (one shared EKEventStore)
                    DashboardWindowController (AppKit) ── window mode only, no business logic
```

| Folder | Contents |
|---|---|
| `App/` | `AppModel` (dependency wiring), `AppDelegate`, menu commands, status-bar menu, `PreferencesStore` |
| `Window/` | `DashboardWindowController`: owns the window and applies Desktop or Normal mode |
| `Models/` | `Reminder`, `ReminderDue` (date + optional time), `ReminderList`, `TaskDueDate` (date-only), `CalendarEvent` |
| `Calendar/` | `EventStoreHub` (the single `EKEventStore` and its queue), `EventKitCalendarRepository`, mock, `CalendarStore` |
| `Reminders/` | `RemindersRepository` protocol, `EventKitRemindersRepository`, mock, `RemindersStore` |
| `Support/` | `CalendarMath` (DST-safe day/month arithmetic), `ReminderGrouper`, `Log` |
| `Views/` | Root layout, reminders panel, calendar panel, settings |

How writes work (`RemindersStore`):

- A change shows immediately with a spinner. It's written to EventKit and the saved reminder is read back as the truth.
- Edits write **only the fields you changed**, so an edit made on your iPhone to a different field is never overwritten.
- Writes to the same reminder run strictly in order. A failure restores the row, shows a Retry banner, and re-reads the store.
- New reminders show as a placeholder until saved. If saving fails, the text is kept in the Retry banner.
- Read-only lists (some shared or Exchange lists) can be viewed but not changed.

## App icon

Drawn in code by `tools/make-icon.swift` (gradient tile, frosted card with a checklist and a mini calendar). The 1024-px master is `docs/icon-1024.png`; the ten sizes live in `DeskDash/Resources/Assets.xcassets/AppIcon.appiconset`. To redraw it after editing the script:

```bash
swift tools/make-icon.swift docs/icon-1024.png
```

Then regenerate each size with `sips -z <px> <px> docs/icon-1024.png --out <file>`, using the file names in `Contents.json`.

## Privacy

- No network access at all: the app has no network entitlement and makes no network calls.
- Sandboxed with one data entitlement, `personal-information.calendars`, which covers both events and reminders in EventKit.
- Logs (`log stream --predicate 'subsystem == "net.hungngo.DeskDash"'`) record counts, timings and failures only, never reminder or event content.

## Not done yet / not verified

- **Real Reminders data**: needs you to click **Allow Reminders Access…** once. Verified with sample data and unit tests. Real Calendar data is verified.
- **iCloud round trip**: add or complete a reminder on the dashboard, then check your iPhone, and the other way round.
- **Desktop-mode interaction checks** that need a person: clicking and typing while other apps are open, Mission Control, Spaces, Stage Manager, full-screen apps, unplugging a display, sleep/wake. Window layering is verified.
- **Distribution**: builds are signed with Apple Development. For other Macs, switch to Developer ID and notarise.
- **Read-only events**: subscribed, holiday and birthday calendars, and invitations organised by someone else, show a lock and the reason.
- **Deferred**: deleting events or reminders, event alerts and custom repeat patterns from DeskDash, moving reminders between lists, notifications from DeskDash itself, AI features, multi-monitor layouts.
