import SwiftUI

/// Card background used by both panels. In desktop mode the background follows the
/// user's transparency and blur settings; in window mode it's an opaque surface.
struct PanelCard: ViewModifier {
    let mode: WindowMode
    @Environment(PreferencesStore.self) private var preferences
    /// With Reduce Transparency on, system blurs draw as solid grey, so use the tint alone.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if mode == .desktop {
            let transparency = preferences.desktopTransparency
            let blur = preferences.desktopBlur && !reduceTransparency
            content
                .readableOverWallpaper(DesktopStyle.needsTextOutline(transparency: transparency, blur: blur))
                .background {
                    ZStack {
                        if DesktopStyle.showsBlur(transparency: transparency, blur: blur) {
                            VisualEffectBlur(cornerRadius: 16)
                        }
                        shape.fill(Color(nsColor: .windowBackgroundColor)
                            .opacity(DesktopStyle.tintOpacity(transparency: transparency, blur: blur)))
                    }
                }
                .overlay {
                    // A hairline edge while there's a visible panel; gone when fully clear.
                    shape.strokeBorder(Color.primary.opacity(transparency > 0.85 ? 0 : 0.07), lineWidth: 1)
                }
                .clipShape(shape)
        } else {
            content
                .background {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5))
                }
                .clipShape(shape)
        }
    }
}

extension View {
    func panelCard(_ mode: WindowMode) -> some View {
        modifier(PanelCard(mode: mode))
    }
}

/// Explains why a panel is empty and what to do about it.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            actions()
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Inline message strip with optional retry and dismiss.
struct BannerView: View {
    let message: String
    var systemImage = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var actionTitle: String?
    var action: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Small icon-only toolbar button with a tooltip and VoiceOver label.
struct IconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Hollow controls

/// Outline-only button: a coloured capsule border and coloured label, no fill,
/// so the wallpaper shows through in desktop mode.
struct HollowButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(tint.opacity(configuration.isPressed ? 0.5 : 0.9), lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A segmented choice where the selected option is outlined, not filled.
struct HollowSegmentedPicker<Value: Hashable & Identifiable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? tint : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .overlay {
                            if selected {
                                Capsule().strokeBorder(tint, lineWidth: 1.5)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // The system focus ring would draw a second, filled-looking outline.
                .focusEffectDisabled()
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
