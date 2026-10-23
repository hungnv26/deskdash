import AppKit
import SwiftUI

/// How desktop-mode panels are drawn for a given transparency (0 solid … 1 clear).
///
/// Only backgrounds fade; text and icons always draw at full opacity. When the
/// background gets thin enough that wallpaper detail could compete with text,
/// a soft outline is added so text stays legible on any wallpaper.
enum DesktopStyle {
    /// Opacity of the tint layer over the (optional) blur.
    static func tintOpacity(transparency: Double, blur: Bool) -> Double {
        let solidness = 1 - min(max(transparency, 0), 1)
        return blur ? 0.6 * solidness : 0.92 * solidness
    }

    /// Whether the blur is drawn at all. Fully clear means no blur either.
    static func showsBlur(transparency: Double, blur: Bool) -> Bool {
        blur && transparency < 0.98
    }

    /// Text needs an outline once the backdrop behind it is mostly raw wallpaper.
    static func needsTextOutline(transparency: Double, blur: Bool) -> Bool {
        showsBlur(transparency: transparency, blur: blur) ? transparency >= 0.9 : transparency >= 0.4
    }
}

/// A live, behind-window blur. `state = .active` keeps it frosted even when another
/// app is in front, which is most of the time for a desktop-layer window.
struct VisualEffectBlur: NSViewRepresentable {
    /// `.sidebar` is the lightest adaptive material: wallpaper colour shows through, detail doesn't.
    var material: NSVisualEffectView.Material = .sidebar
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = cornerRadius > 0
    }
}

/// A soft outline that keeps text readable over busy wallpaper.
struct ReadableOverWallpaper: ViewModifier {
    let enabled: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: colorScheme == .dark ? .black.opacity(0.75) : .white.opacity(0.9), radius: 1.5, x: 0, y: 0)
                .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : .white.opacity(0.5), radius: 4, x: 0, y: 0)
        } else {
            content
        }
    }
}

extension View {
    func readableOverWallpaper(_ enabled: Bool) -> some View {
        modifier(ReadableOverWallpaper(enabled: enabled))
    }
}

// MARK: - Fading chrome

private struct ChromeVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False when desktop mode hides controls until the pointer is over the dashboard.
    var chromeVisible: Bool {
        get { self[ChromeVisibleKey.self] }
        set { self[ChromeVisibleKey.self] = newValue }
    }
}

/// Fades secondary controls out when they aren't needed. Layout never moves.
struct FadingChrome: ViewModifier {
    var forceVisible = false
    @Environment(\.chromeVisible) private var chromeVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = chromeVisible || forceVisible
        content
            .opacity(visible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: visible)
    }
}

extension View {
    func fadingChrome(forceVisible: Bool = false) -> some View {
        modifier(FadingChrome(forceVisible: forceVisible))
    }
}

/// Reports when the pointer enters or leaves the view, even while the app is inactive
/// (SwiftUI's `onHover` only fires for the active app). Never takes clicks.
struct PointerTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onChange: onChange)
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void
        private var area: NSTrackingArea?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
