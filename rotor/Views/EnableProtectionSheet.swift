import SwiftUI

struct EnableProtectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var confirm: String = ""
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false
    @FocusState private var firstFieldFocused: Bool

    private var canProceed: Bool {
        password.count >= 8 && password == confirm && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.rotorPrimary)
                Text("开启保护模式")
                    .font(.system(size: 16, weight: .semibold))
            }

            Text("保护模式会用主密码加密本机的 TOTP 秘钥，并在空闲时自动锁定。主密码丢失后无法恢复账户，请妥善保管。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("主密码（至少 8 位）", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($firstFieldFocused)
            SecureField("重复主密码", text: $confirm)
                .textFieldStyle(.roundedBorder)
                .onSubmit(proceed)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.system(size: 12))
            } else if !password.isEmpty && !confirm.isEmpty && password != confirm {
                Text("两次输入的密码不一致").foregroundStyle(.red).font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: proceed) {
                    if isWorking {
                        ProgressView().controlSize(.small).frame(width: 80, height: 20)
                    } else {
                        Text("开启").frame(width: 80, height: 20)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canProceed)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { firstFieldFocused = true }
    }

    private func proceed() {
        guard canProceed else { return }
        errorMessage = nil
        isWorking = true
        let pw = password
        let cf = confirm
        Task.detached {
            do {
                try await MainActor.run {
                    try VaultManager.shared.enableProtection(password: pw, confirm: cf)
                }
                await MainActor.run {
                    isWorking = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "操作失败"
                }
            }
        }
    }
}
