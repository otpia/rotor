import AppKit
import Combine
import SwiftUI

struct AccountCard: View {
    let account: AccountModel
    var compact: Bool = false
    var onCopy: ((AccountModel, String) -> Void)? = nil

    @State private var generator: TOTPGenerator?
    @State private var code: String = "------"
    @State private var secondsRemaining: Double = 30
    @State private var isHovered: Bool = false
    @State private var showCopied: Bool = false

    private var progress: Double {
        guard let g = generator else { return 0 }
        return secondsRemaining / g.period
    }
    private var isExpiring: Bool { secondsRemaining <= 5 }
    private var codeColor: Color { isExpiring ? .rotorDanger : .primary }
    private var codeFont: Font { compact ? .rotorCodeCompact : .rotorCode }
    // 把码按前 3 / 后 3 拆开，避免等宽空格占位过宽
    private var firstHalf: String {
        code.count >= 3 ? String(code.prefix(3)) : code
    }
    private var secondHalf: String {
        code.count > 3 ? String(code.suffix(code.count - 3)) : ""
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                HStack(spacing: 8) {
                    Image(systemName: account.iconSymbol)
                        .font(.system(size: compact ? 14 : 16, weight: .semibold))
                        .foregroundStyle(account.iconTint)
                        .frame(width: 20, height: 20)
                    Text(account.issuer)
                        .font(.rotorIssuer)
                        .foregroundStyle(.primary)
                }
                HStack(spacing: compact ? 6 : 10) {
                    Text(firstHalf)
                        .font(codeFont)
                        .foregroundStyle(codeColor)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: code)
                    Text(secondHalf)
                        .font(codeFont)
                        .foregroundStyle(codeColor)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: code)
                }
                Text(account.label)
                    .font(.rotorLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            CountdownRing(
                progress: progress,
                isExpiring: isExpiring,
                diameter: compact ? 22 : RotorTheme.ringDiameter,
                stroke: compact ? 2.5 : RotorTheme.ringStroke
            )
        }
        .padding(compact ? 12 : RotorTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: RotorTheme.cornerRadius, style: .continuous)
                .fill(isHovered ? Color.rotorCardHover : Color.rotorCard)
                .shadow(color: .black.opacity(isHovered ? 0.06 : 0.03), radius: isHovered ? 6 : 3, y: 1)
        )
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("已复制")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: RotorTheme.cornerRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .onTapGesture { copy() }
        .onAppear {
            generator = account.makeGenerator()
            refresh()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        guard let g = generator else {
            code = "------"
            secondsRemaining = 30
            return
        }
        let newCode = g.code()
        if newCode != code { code = newCode }
        secondsRemaining = g.secondsRemaining()
    }

    private func copy() {
        let plain = code.replacingOccurrences(of: " ", with: "")
        guard plain.allSatisfy({ $0.isNumber }) else { return }
        ClipboardService.shared.copy(plain)
        onCopy?(account, plain)
        withAnimation(.easeOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.2)) { showCopied = false }
        }
    }
}
