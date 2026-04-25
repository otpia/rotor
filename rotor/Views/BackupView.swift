import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupTab: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [AccountModel]

    @State private var exporting = false
    @State private var importRequest: ImportRequest?
    @State private var statusMessage: String?
    @State private var importProgress: AccountImportService.Progress?
    @State private var showingPurgeConfirm = false

    private struct ImportRequest: Identifiable {
        let id = UUID()
        let fileURL: URL
    }

    private enum ThirdPartyKind {
        case aegis
        case twofas
        var displayName: String {
            switch self {
            case .aegis:  return "Aegis"
            case .twofas: return "2FAS"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("加密备份") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("使用主密码加密为 .rotor 文件。文件采用 Argon2id（64 MiB / 3 轮）+ AES-256-GCM；其他设备上输入同样密码即可还原。仍可读取旧版 PBKDF2 备份。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            exporting = true
                        } label: {
                            Label("导出为 .rotor 文件…", systemImage: "square.and.arrow.up")
                        }
                        .disabled(accounts.isEmpty)

                        Button {
                            pickImportFile()
                        } label: {
                            Label("从 .rotor 文件导入…", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("从其他 App 导入") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("目前支持 Aegis 和 2FAS 的未加密 JSON 备份；加密备份请先在对应 App 中解锁导出。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            importThirdParty(.aegis)
                        } label: {
                            Label("从 Aegis 导入…", systemImage: "tray.and.arrow.down")
                        }
                        Button {
                            importThirdParty(.twofas)
                        } label: {
                            Label("从 2FAS 导入…", systemImage: "tray.and.arrow.down")
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("危险操作") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("立即删除本机所有账户。无法撤销 — 强烈建议先在上方导出 .rotor 备份。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showingPurgeConfirm = true
                    } label: {
                        Label("清空所有账户…", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(accounts.isEmpty)
                }
                .padding(6)
            }

            if let status = statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .alert("清空所有账户?", isPresented: $showingPurgeConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                purgeAll()
            }
        } message: {
            Text("将删除全部 \(accounts.count) 个账户，此操作无法撤销。")
        }
        .overlay {
            if let progress = importProgress {
                ProgressOverlay(progress: progress)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: importProgress)
        .sheet(isPresented: $exporting) {
            ExportPromptSheet(accounts: accounts) { message in
                statusMessage = message
            }
        }
        .sheet(item: $importRequest) { request in
            ImportPromptSheet(fileURL: request.fileURL) { message in
                statusMessage = message
            }
        }
    }

    private func importThirdParty(_ kind: ThirdPartyKind) {
        let panel = NSOpenPanel()
        panel.title = "选择 \(kind.displayName) 备份 JSON"
        panel.allowedContentTypes = [.json, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        importProgress = AccountImportService.Progress(current: 0, total: 0, stage: "正在解析 \(kind.displayName) 文件…")
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: url)
                let candidates: [AccountImportService.Candidate]
                switch kind {
                case .aegis:  candidates = try AegisImporter.parse(data)
                case .twofas: candidates = try TwoFASImporter.parse(data)
                }
                guard !candidates.isEmpty else {
                    importProgress = nil
                    statusMessage = "\(kind.displayName) 文件中未发现 TOTP 账户"
                    return
                }
                let outcome = try await AccountImportService.performImport(
                    items: candidates,
                    into: context
                ) { p in
                    importProgress = p
                }
                importProgress = nil
                var parts = ["已从 \(kind.displayName) 导入 \(outcome.inserted) 个账户"]
                if outcome.skipped > 0 { parts.append("跳过 \(outcome.skipped) 个重复") }
                if outcome.failed > 0  { parts.append("\(outcome.failed) 个失败") }
                statusMessage = parts.joined(separator: "，")
            } catch {
                importProgress = nil
                statusMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private func purgeAll() {
        let count = accounts.count
        for account in accounts {
            context.delete(account)
        }
        try? context.save()
        statusMessage = "已清空 \(count) 个账户"
    }

    private func pickImportFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 .rotor 备份文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK, let url = panel.url {
            importRequest = ImportRequest(fileURL: url)
        }
    }
}

struct ExportPromptSheet: View {
    let accounts: [AccountModel]
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var confirm: String = ""
    @State private var errorMessage: String?

    private var canExport: Bool {
        password.count >= 8 && password == confirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导出加密备份").font(.system(size: 16, weight: .semibold))
            Text("将导出 \(accounts.count) 个账户。请妥善保管主密码，丢失后备份将无法还原。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SecureField("主密码（至少 8 位）", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("重复主密码", text: $confirm)
                .textFieldStyle(.roundedBorder)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.system(size: 12))
            } else if !password.isEmpty && !confirm.isEmpty && password != confirm {
                Text("两次输入的密码不一致").foregroundStyle(.red).font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导出") { performExport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canExport)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func performExport() {
        do {
            let data = try BackupService.export(accounts: accounts, password: password)
            let panel = NSSavePanel()
            panel.title = "保存 .rotor 备份"
            panel.nameFieldStringValue = "rotor-backup-\(Self.dateString()).rotor"
            panel.allowedContentTypes = [.data]
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url, options: .atomic)
                onComplete("已导出 \(accounts.count) 个账户到 \(url.lastPathComponent)")
                dismiss()
            }
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private static func dateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        return fmt.string(from: Date())
    }
}

struct ImportPromptSheet: View {
    let fileURL: URL
    let onComplete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var importProgress: AccountImportService.Progress?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入加密备份").font(.system(size: 16, weight: .semibold))
            Text("文件：\(fileURL.lastPathComponent)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            SecureField("主密码", text: $password)
                .textFieldStyle(.roundedBorder)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.system(size: 12))
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("导入") { performImport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || importProgress != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .overlay {
            if let progress = importProgress {
                ProgressOverlay(progress: progress)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: importProgress)
    }

    private func performImport() {
        importProgress = AccountImportService.Progress(current: 0, total: 0, stage: "正在解密备份…")
        Task { @MainActor in
            do {
                let data = try Data(contentsOf: fileURL)
                let items = try BackupService.import(from: data, password: password)
                let candidates = items.map { item in
                    AccountImportService.Candidate(
                        id: item.id,
                        issuer: item.issuer,
                        label: item.label,
                        secretBase32: item.secret,
                        digits: item.digits,
                        period: item.period,
                        algorithm: TOTPAlgorithm(rawValue: item.algorithm) ?? .sha1,
                        iconSymbol: item.iconSymbol,
                        iconTintHex: item.iconTintHex,
                        sortOrder: item.sortOrder,
                        createdAt: item.createdAt
                    )
                }
                let outcome = try await AccountImportService.performImport(
                    items: candidates,
                    into: context
                ) { p in
                    importProgress = p
                }
                importProgress = nil

                var parts: [String] = ["已导入 \(outcome.inserted) 个账户"]
                if outcome.skipped > 0 { parts.append("跳过 \(outcome.skipped) 个重复") }
                if outcome.failed > 0  { parts.append("\(outcome.failed) 个失败") }
                onComplete(parts.joined(separator: "，"))
                dismiss()
            } catch {
                importProgress = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}
