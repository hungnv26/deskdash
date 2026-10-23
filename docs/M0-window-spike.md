# M0: desktop-window spike

**Date:** 19 Oct 2026 · **macOS:** 27.0.1 (26A434) · **Hardware:** built-in 1728×1117 display (primary) plus a 2560×1440 external display

## Question

Can a public-API AppKit window behave like an interactive layer of the desktop: behind every app window, visible on all Spaces, and still clickable and typeable?

## Approach

`DesktopDashboardWindow` is a borderless `NSWindow` subclass that overrides `canBecomeKey` (so text fields work) and returns false for `canBecomeMain`. It is configured with:

- `level`: `CGWindowLevelForKey(.desktopIconWindow) + 1` (default), or `- 1` for the "behind desktop icons" option
- `collectionBehavior`: `.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone`
- transparent background, no shadow, not movable, `hidesOnDeactivate = false`
- frame = primary display's `visibleFrame` inset 24 pt, so it stays clear of the menu bar and Dock

It is shown with `orderFrontRegardless()`, which only reorders it within its own level.

## Results

Measured with `CGWindowListCopyWindowInfo` (z-order and layer) and `screencapture -l` (window image):

| Check | Result |
|---|---|
| Layer | DeskDash at −2147483602 (icon level + 1). Finder desktop-icon windows at −2147483603, wallpaper (WindowManager) at −2147483624 |
| Z-order | Every normal (layer 0) window, including Finder windows, is listed above DeskDash, and DeskDash is above Finder's desktop-icon window |
| Placement | 24, 58, 1680×1035 on the primary display: inside the visible frame, clear of the menu bar and Dock |
| Rendering | SwiftUI content draws correctly in the borderless window (screenshot verified) |
| Mode switch | Rebuilds the window around the same shared stores, so the selected date, list and preferences carry over |
| Display change / wake | Repositions on `didChangeScreenParametersNotification` and `didWakeNotification`; a normal window that ends up off-screen is re-centred |

**Not yet tested by hand:** clicks and typing with real input, Mission Control, Spaces switching, Stage Manager, full-screen apps, unplugging a display. Synthetic input needs Accessibility permission, which the spec rules out, so these need a quick manual pass. Use the README's "Desktop mode" section as the checklist.

## Decision

- **Default:** interactive layer just above desktop icons. It is fully clickable and covers the icons, and is the closest public-API match to "wallpaper-like but interactive".
- **Option:** behind desktop icons. Icons stay visible, but Finder receives the clicks, so it is display-only. The Settings text says so plainly instead of implying it's interactive.
- **Fallback:** Normal window mode is always one keystroke away (⌥⌘N, or the menu-bar icon's **Return to Normal Window**), and is the default on first launch.

No private APIs. No Accessibility or Screen Recording permission requested.
