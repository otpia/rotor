import SwiftUI

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirm: String = ""
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false

    private var canProceed: Bool {
        !oldPassword.isEmpty
            && newPassword.count >= 8
            && newPassword == confirm
            && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("修改主密码").font(.system(size: 16, weight: .semibold))

            SecureField("当前主密码", text: $oldPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("新主密码（至少 8 位）", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("重复新主密码", text: $confirm)
                .textFieldStyle(.roundedBorder)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.system(size: 12))
            } else if !newPassword.isEmpty && !confirm.isEmpty && newPassword != confirm {
                Text("两次新密码不一致").foregroundStyle(.red).font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: proceed) {
                    if isWorking {
                        ProgressView().controlSize(.small).frame(width: 80, height: 20)
                    } else {
                        Text("修改").frame(width: 80, height: 20)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canProceed)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func proceed() {
        guard canProceed else { return }
        errorMessage = nil
        isWorking = true
        let old = oldPassword
        let new = newPassword
        let cf = confirm
        Task.detached {
            do {
                try await MainActor.run {
                    try VaultManager.shared.changePassword(oldPassword: old, newPassword: new, confirm: cf)
                }
                await MainActor.run {
                    isWorking = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "修改失败"
                }
            }
        }
    }
}
