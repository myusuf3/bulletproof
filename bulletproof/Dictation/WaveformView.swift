import SwiftUI

/// Live voice wave: the newest loudness sits in the middle and older
/// readings ripple out to both edges, so speech visibly pulses from the
/// center. Shared by the dictation overlay, Settings, and onboarding.
struct WaveformView: View {
    let levels: [Float]
    var tint: Color = .primary
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let fitting = Int((proxy.size.width + spacing) / (barWidth + spacing))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(Self.bars(from: levels, count: fitting).enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth, height: max(barWidth, CGFloat(level) * height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.12), value: levels)
        }
        .accessibilityHidden(true)
    }

    /// Mirrors history (oldest first) so the newest reading lands in the
    /// center and age increases toward both edges, tapering off there. At
    /// most `count` bars, so the wave always fits its frame.
    nonisolated static func bars(from history: [Float], count: Int) -> [Float] {
        let half = Array(history.suffix(min(history.count, count) / 2).reversed())
        guard !half.isEmpty else { return [] }
        let right = half.enumerated().map { index, level in
            level * (1 - 0.6 * Float(index) / Float(half.count))
        }
        return right.reversed() + right
    }
}
