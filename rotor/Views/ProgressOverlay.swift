import SwiftUI

// 半透明遮罩 + 居中进度条，覆盖 sheet 内容
struct ProgressOverlay: View {
    let progress: AccountImportService.Progress

    private var ratio: Double {
        guard progress.total > 0 else { return 0 }
        return min(1, Double(progress.current) / Double(progress.total))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: ratio)
                    .progressViewStyle(.linear)
                    .tint(.rotorPrimary)
                    .frame(width: 240)
                Text(progress.stage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .transition(.opacity)
    }
}
