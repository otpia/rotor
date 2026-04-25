import SwiftUI

// Countdown ring: `progress` is the remaining-time ratio (1 = full, 0 = expired); switches to danger red when expiring
struct CountdownRing: View {
    var progress: Double
    var isExpiring: Bool
    var diameter: CGFloat = RotorTheme.ringDiameter
    var stroke: CGFloat   = RotorTheme.ringStroke

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    isExpiring ? Color.rotorDanger : Color.primary.opacity(0.85),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: progress)
        }
        .frame(width: diameter, height: diameter)
    }
}
