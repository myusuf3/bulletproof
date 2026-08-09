import SwiftUI

/// A single on-screen key that visually travels down when its physical key is
/// held, and flashes green when the chord fires.
struct KeycapView: View {
    let symbol: String
    var label: String? = nil
    var isPressed = false
    var isSuccess = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            Text(symbol)
                .font(.system(size: 20, weight: .medium, design: .rounded))
            if let label {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 50)
        // Fixed height keeps labeled and unlabeled caps aligned in a row.
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSuccess ? Color.green.opacity(0.22)
                                : Color(nsColor: .controlBackgroundColor))
                // Two shadows: a tight contact shadow plus a soft drop shadow.
                // Pressing collapses the drop, which sells the key travel.
                .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                .shadow(color: .black.opacity(isPressed ? 0.05 : 0.18),
                        radius: isPressed ? 1 : 4, y: isPressed ? 1 : 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.separator.opacity(0.6)))
        .overlay(
            // Top-edge highlight carries the depth cue in dark mode, where
            // black drop shadows have almost no contrast.
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(isPressed ? 0.08 : 0.25), .clear],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.green, lineWidth: isSuccess ? 2 : 0))
        .offset(y: isPressed && !reduceMotion ? 3 : 0)
        .animation(.spring(duration: 0.12, bounce: 0.25), value: isPressed)
        .animation(.spring(duration: 0.3), value: isSuccess)
    }
}

/// A chord rendered as keycaps: modifiers in canonical ⌃⌥⇧⌘ order, then the
/// key. Modifier caps depress live from pressedModifiers; the key cap only
/// flashes green with the rest on fire (Carbon consumes its keyDown, so it is
/// never observed live).
struct KeycapRow: View {
    let combo: KeyCombo
    var pressedModifiers: NSEvent.ModifierFlags = []
    var isSuccess = false

    private static let modifierInfo: [(flag: NSEvent.ModifierFlags, symbol: String, label: String)] = [
        (.control, "⌃", "control"),
        (.option, "⌥", "option"),
        (.shift, "⇧", "shift"),
        (.command, "⌘", "command"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.modifierInfo.filter { combo.modifiers.contains($0.flag) }, id: \.symbol) { info in
                KeycapView(symbol: info.symbol, label: info.label,
                           isPressed: pressedModifiers.contains(info.flag) || isSuccess,
                           isSuccess: isSuccess)
                plus
            }
            KeycapView(symbol: KeyCombo.keySymbol(for: combo.keyCode),
                       isPressed: isSuccess, isSuccess: isSuccess)
        }
    }

    private var plus: some View {
        Text("+")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.tertiary)
    }
}
