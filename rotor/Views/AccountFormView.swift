import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AccountFormMode: Hashable {
    case new
    case edit(AccountModel)
}

struct AccountFormView: View {
    let mode: AccountFormMode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var issuer: String
    @State private var label: String
    @State private var secretBase32: String = ""
    @State private var digits: Int
    @State private var period: Double
    @State private var algorithm: TOTPAlgorithm
    @State private var group: String
    @State private var pasteText: String = ""
    @State private var errorMessage: String?
    @State private var importProgress: AccountImportService.Progress?

    init(mode: AccountFormMode = .new) {
        self.mode = mode
        switch mode {
        case .new:
            _issuer    = State(initialValue: "")
            _label     = State(initialValue: "")
            _digits    = State(initialValue: 6)
            _period    = State(initialValue: 30)
            _algorithm = State(initialValue: .sha1)
            _group     = State(initialValue: "")
        case .edit(let account):
            _issuer    = State(initialValue: account.issuer)
            _label     = State(initialValue: account.label)
            _digits    = State(initialValue: account.digits)
            _period    = State(initialValue: account.period)
            _algorithm = State(initialValue: account.algorithm)
            _group     = State(initialValue: account.group)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var windowTitle: String { isEditing ? "编辑账户" : "添加账户" }

    private var canSave: Bool {
        let issuerOK = !issuer.trimmingCharacters(in: .whitespaces).isEmpty
        let trimmed = secretBase32.trimmingCharacters(in: .whitespaces)
        if isEditing {
            // 编辑时 secret 可留空表示不变；填了必须是合法 Base32
            let secretOK = trimmed.isEmpty || Base32.decode(trimmed) != nil
            return issuerOK && secretOK
        } else {
            return issuerOK && !trimmed.isEmpty && Base32.decode(trimmed) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(windowTitle).font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            if !isEditing {
                quickImportSection
            }
            formSection

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "保存修改" : "保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460, height: isEditing ? 480 : 600)
        .background(Color.rotorBackground)
        .overlay {
            if let progress = importProgress {
                ProgressOverlay(progress: progress)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: importProgress)
    }

    private var quickImportSection: some View {
        GroupBox("快速导入") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("粘贴 otpauth:// URI", text: $pasteText)
                        .textFieldStyle(.roundedBorder)
                    Button("解析", action: applyURI)
                        .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    pickQRImage()
                } label: {
                    Label("从二维码图片导入…（可多选）", systemImage: "qrcode.viewfinder")
                }
            }
            .padding(6)
        }
    }

    private var formSection: some View {
        GroupBox("账户") {
            VStack(alignment: .leading, spacing: 10) {
                labeled("名称") {
                    TextField("例如：Google", text: $issuer)
                        .textFieldStyle(.roundedBorder)
                }
                labeled("描述") {
                    TextField("例如：user@example.com", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                labeled("秘钥") {
                    TextField(
                        isEditing ? "留空保持不变" : "Base32 字符串",
                        text: $secretBase32
                    )
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
                }
                labeled("算法") {
                    Picker("", selection: $algorithm) {
                        Text("SHA1").tag(TOTPAlgorithm.sha1)
                        Text("SHA256").tag(TOTPAlgorithm.sha256)
                        Text("SHA512").tag(TOTPAlgorithm.sha512)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                labeled("位数") {
                    numberField(binding: digitsBinding, range: 6...8, step: 1)
                }
                labeled("周期") {
                    numberField(binding: periodBinding, range: 15...120, step: 15, suffix: "秒")
                }
                labeled("分组") {
                    TextField("可选，如：工作 / 个人", text: $group)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(6)
        }
    }

    // 手动输入和箭头共用同一 Binding；写入时 clamp 到允许范围，越界输入自动回落
    private var digitsBinding: Binding<Int> {
        Binding(
            get: { digits },
            set: { digits = min(max($0, 6), 8) }
        )
    }

    private var periodBinding: Binding<Int> {
        Binding(
            get: { Int(period) },
            set: { period = TimeInterval(min(max($0, 15), 120)) }
        )
    }

    @ViewBuilder
    private func numberField(
        binding: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            TextField("", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 56)
            Stepper("", value: binding, in: range, step: step)
                .labelsHidden()
                .controlSize(.mini)
            if let suffix {
                Text(suffix)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            content()
        }
    }

    // 单/多 payload 统一的中间结果
    private struct ExtractedItem {
        let issuer: String?
        let label: String
        let secretBase32: String
        let digits: Int
        let period: TimeInterval
        let algorithm: TOTPAlgorithm
    }

    private func applyURI() {
        let items = extractItems(from: [pasteText])
        if items.isEmpty {
            errorMessage = "无法解析该 URI"
            return
        }
        if items.count > 1 {
            // 粘贴 GA migration URI 且包含多账户：直接批量入库
            handleBulk(items)
        } else {
            fillForm(from: items[0])
            errorMessage = nil
        }
    }

    private func pickQRImage() {
        let panel = NSOpenPanel()
        panel.title = "选择包含二维码的图片"
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var payloads: [String] = []
        for url in panel.urls {
            payloads.append(contentsOf: QRImageDecoder.decode(url))
        }
        let items = extractItems(from: payloads)
        if items.isEmpty {
            errorMessage = "图片中未识别到账户二维码"
            return
        }
        if items.count == 1 {
            fillForm(from: items[0])
            errorMessage = nil
        } else {
            handleBulk(items)
        }
    }

    // 把任意数量 URI / QR payload 展开为 ExtractedItem 列表
    // 支持 otpauth:// 单条 和 otpauth-migration:// 多条（GA 导出）
    private func extractItems(from payloads: [String]) -> [ExtractedItem] {
        var result: [ExtractedItem] = []
        for payload in payloads {
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if GoogleAuthMigrationParser.isMigrationURI(trimmed) {
                if let migrationItems = GoogleAuthMigrationParser.parse(trimmed) {
                    for mi in migrationItems {
                        result.append(ExtractedItem(
                            issuer: mi.issuer,
                            label: mi.label,
                            secretBase32: Base32.encode(mi.secret),
                            digits: mi.digits,
                            period: mi.period,
                            algorithm: mi.algorithm
                        ))
                    }
                }
                continue
            }

            if let parsed = OTPAuthParser.parse(trimmed) {
                result.append(ExtractedItem(
                    issuer: parsed.issuer,
                    label: parsed.label,
                    secretBase32: parsed.secretBase32,
                    digits: parsed.digits,
                    period: parsed.period,
                    algorithm: parsed.algorithm
                ))
            }
        }
        return result
    }

    private func fillForm(from item: ExtractedItem) {
        issuer = item.issuer ?? issuer
        label = item.label
        secretBase32 = item.secretBase32
        digits = item.digits
        period = item.period
        algorithm = item.algorithm
    }

    // 批量入库：委托给 AccountImportService（统一去重 + 进度）
    private func handleBulk(_ items: [ExtractedItem]) {
        let candidates = items.map { item in
            AccountImportService.Candidate(
                issuer: item.issuer,
                label: item.label,
                secretBase32: item.secretBase32,
                digits: item.digits,
                period: item.period,
                algorithm: item.algorithm
            )
        }
        importProgress = AccountImportService.Progress(current: 0, total: candidates.count, stage: "准备导入…")

        Task { @MainActor in
            do {
                let outcome = try await AccountImportService.performImport(
                    items: candidates,
                    into: context
                ) { p in
                    importProgress = p
                }
                importProgress = nil

                if outcome.inserted > 0 {
                    dismiss()
                    return
                }
                // 全部跳过或失败，不 dismiss，给用户看原因
                if outcome.skipped > 0 && outcome.failed == 0 {
                    errorMessage = "所选二维码中的 \(outcome.skipped) 个账户已存在"
                } else {
                    errorMessage = "导入失败（\(outcome.failed) 个错误，\(outcome.skipped) 个已存在）"
                }
            } catch {
                importProgress = nil
                errorMessage = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    private func save() {
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespaces)
        let trimmedLabel  = label.trimmingCharacters(in: .whitespaces)
        let trimmedSecret = secretBase32.trimmingCharacters(in: .whitespaces)
        let trimmedGroup  = group.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .new:
            guard let secret = Base32.decode(trimmedSecret) else {
                errorMessage = "Base32 秘钥格式错误"
                return
            }
            do {
                let ct = try SecretVault.encrypt(secret)
                let nextOrder = (try? context.fetch(FetchDescriptor<AccountModel>()).count) ?? 0
                let model = AccountModel(
                    issuer: trimmedIssuer,
                    label: trimmedLabel,
                    digits: digits,
                    period: period,
                    algorithm: algorithm,
                    sortOrder: nextOrder,
                    group: trimmedGroup,
                    ciphertext: ct
                )
                context.insert(model)
                try context.save()
                dismiss()
            } catch {
                errorMessage = "保存失败：\(error.localizedDescription)"
            }

        case .edit(let account):
            account.issuer = trimmedIssuer
            account.label  = trimmedLabel
            account.digits = digits
            account.period = period
            account.algorithm = algorithm
            account.group  = trimmedGroup

            if !trimmedSecret.isEmpty {
                guard let secret = Base32.decode(trimmedSecret) else {
                    errorMessage = "Base32 秘钥格式错误"
                    return
                }
                do {
                    account.ciphertext = try SecretVault.encrypt(secret)
                } catch {
                    errorMessage = "加密失败：\(error.localizedDescription)"
                    return
                }
            }
            do {
                try context.save()
                dismiss()
            } catch {
                errorMessage = "保存失败：\(error.localizedDescription)"
            }
        }
    }
}
