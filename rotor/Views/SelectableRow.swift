import SwiftUI

// Compact row for the bulk-select mode: checkbox + icon + issuer + label, no TOTP
struct SelectableRow: View {
    let account: AccountModel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(isSelected ? Color.rotorPrimary : Color.secondary.opacity(0.5))

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.rotorPrimary.opacity(0.10) : Color.rotorCard)
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.rotorPrimary.opacity(0.5) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
    }
}
