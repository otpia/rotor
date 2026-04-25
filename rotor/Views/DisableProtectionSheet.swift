import SwiftUI

struct DisableProtectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false
    @FocusState private var fieldFocused: Bool

    private var canProceed: Bool {
        !password.isEmpty && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                Text("关闭保护模式")
                    .font(.system(size: 16, weight: .semibold))
            }

            Text("关闭后 Rotor 不再要求输入主密码，也不会自动锁定。需输入当前主密码确认。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("当前主密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(proceed)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: proceed) {
                    if isWorking {
                        ProgressView().controlSize(.small).frame(width: 80, height: 20)
                    } else {
                        Text("关闭保护").frame(width: 80, height: 20)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canProceed)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { fieldFocused = true }
    }

    private func proceed() {
        guard canProceed else { return }
        errorMessage = nil
        isWorking = true
        let pw = password
        Task.detached {
            do {
                try await MainActor.run {
                    try VaultManager.shared.disableProtection(password: pw)
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
