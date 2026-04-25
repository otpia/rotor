import SwiftUI

struct LockScreenView: View {
    @State private var vault = VaultManager.shared
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isUnlocking: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.rotorPrimary)
                .padding(.bottom, 2)

            Text("Rotor 已锁定")
                .font(.system(size: 18, weight: .semibold))
            Text("输入主密码以解锁")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SecureField("主密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .focused($fieldFocused)
                .onSubmit(attemptUnlock)

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Button(action: attemptUnlock) {
                if isUnlocking {
                    ProgressView().controlSize(.small)
                        .frame(width: 80, height: 24)
                } else {
                    Text("解锁")
                        .frame(width: 80, height: 24)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(password.isEmpty || isUnlocking)

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rotorBackground)
        .onAppear { fieldFocused = true }
    }

    private func attemptUnlock() {
        guard !password.isEmpty, !isUnlocking else { return }
        errorMessage = nil
        isUnlocking = true
        // Argon2id 派生 ~0.5-1s，放到后台不阻塞主线程
        let pw = password
        Task.detached {
            do {
                try await MainActor.run { try VaultManager.shared.unlock(password: pw) }
                await MainActor.run {
                    password = ""
                    isUnlocking = false
                }
            } catch {
                await MainActor.run {
                    isUnlocking = false
                    password = ""
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "密码错误"
                    fieldFocused = true
                }
            }
        }
    }
}
