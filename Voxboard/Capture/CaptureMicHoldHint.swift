import SwiftUI

/// The target is measured in the controls' coordinate space, so the hint follows
/// the mic when the keyboard, layout direction, or available width changes.
struct CaptureMicHoldHintAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct CaptureMicHoldHintPlacement {
    let width: CGFloat
    let minX: CGFloat
    let arrowX: CGFloat

    init(containerWidth: CGFloat, micMidX: CGFloat) {
        let margin: CGFloat = 12
        width = min(280, max(0, containerWidth - margin * 2))
        minX = min(max(margin, micMidX - width + 40), max(margin, containerWidth - margin - width))
        arrowX = micMidX - minX
    }
}

/// Presentation only; completion and eligibility stay in QuickCaptureView.
struct CaptureMicHoldHintOverlay: View {
    let micAnchor: Anchor<CGRect>?
    let dismiss: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { geometry in
            if let micAnchor {
                let mic = geometry[micAnchor]
                let placement = CaptureMicHoldHintPlacement(
                    containerWidth: geometry.size.width,
                    micMidX: mic.midX
                )
                CaptureMicHoldHint(
                    arrowX: placement.arrowX,
                    textLayoutDirection: layoutDirection,
                    dismiss: dismiss
                )
                .frame(width: placement.width)
                .fixedSize(horizontal: false, vertical: true)
                // An explicit height keeps even a tall Dynamic Type bubble
                // above the mic instead of letting its ideal size grow down.
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
                .offset(x: placement.minX, y: mic.minY - geometry.size.height - 6)
            }
        }
        // Placement uses physical coordinates from the anchor, including in RTL.
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct CaptureMicHoldHint: View {
    let arrowX: CGFloat
    let textLayoutDirection: LayoutDirection
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bubble
                .environment(\.layoutDirection, textLayoutDirection)
            Image(systemName: "arrow.down")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Geist.Palette.blue900)
                .frame(width: 24, height: 28)
                .offset(x: arrowX - 12)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { arrow, raised in
                    arrow.offset(y: raised ? -4 : 0)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_mic_hold_hint")
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Geist.Palette.blue900)
                .padding(.top, 12)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hold down on mic")
                    .font(Geist.label())
                    .foregroundStyle(Geist.Palette.blue1000)
                Text("Discover recording controls")
                    .font(Geist.caption(.caption2))
                    .foregroundStyle(Geist.Palette.blue900)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Geist.Palette.blue1000)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss microphone tip")
            .accessibilityIdentifier("capture_mic_hold_hint_dismiss")
        }
        .padding(.leading, 12)
        .background(Geist.Palette.blue100, in: RoundedRectangle(cornerRadius: Geist.Radius.large))
        .overlay {
            RoundedRectangle(cornerRadius: Geist.Radius.large)
                .strokeBorder(Geist.Palette.blue500.opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
    }
}
