import SwiftUI

// 倒计时环：progress 表示「剩余时间比例」，1 为满、0 为过期；到期切危险红
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
