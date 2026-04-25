import SwiftUI

// 重排模式专用行：不显示 TOTP / 倒计时环，去掉 Timer 订阅和动画开销
// 高度 48pt，一屏能容纳更多账户
struct ReorderRow: View {
    let account: AccountModel
    let isDragging: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.iconSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(account.iconTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.issuer)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if !account.label.isEmpty {
                    Text(account.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.rotorCard)
                .shadow(
                    color: .black.opacity(isDragging ? 0.22 : 0.03),
                    radius: isDragging ? 14 : 2,
                    y: isDragging ? 6 : 1
                )
        )
    }
}
