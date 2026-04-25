import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var vault = VaultManager.shared
    @State private var showingEnableProtection = false
    @State private var showingDisableProtection = false
    @State private var showingChangePassword = false

    private let autoLockOptions: [(Int, String)] = [
        (0, "永不"),
        (1, "1 分钟"),
        (5, "5 分钟"),
        (15, "15 分钟"),
        (60, "1 小时"),
    ]

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            securityTab
                .tabItem { Label("安全", systemImage: "lock.shield") }
            BackupTab()
                .tabItem { Label("备份", systemImage: "externaldrive") }
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
        .sheet(isPresented: $showingEnableProtection) {
            EnableProtectionSheet()
        }
        .sheet(isPresented: $showingDisableProtection) {
            DisableProtectionSheet()
        }
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordSheet()
        }
    }

    private var generalTab: some View {
        Form {
            Section("窗口置顶") {
                Toggle("主窗口保持在最前", isOn: $settings.mainWindowPinned)
                Toggle("菜单栏 popover 保持在最前", isOn: $settings.popoverPinned)
            }
            Section {
                Toggle("禁止屏幕录制与截图", isOn: $settings.screenCaptureBlocked)
            } header: {
                Text("隐私")
            } footer: {
                Text("启用后，系统截屏、屏幕录制、共享会议中看不到 Rotor 窗口内容。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var securityTab: some View {
        Form {
            Section {
                Toggle("保护模式", isOn: Binding(
                    get: { vault.protectionEnabled },
                    set: { newValue in
                        if newValue {
                            showingEnableProtection = true
                        } else {
                            showingDisableProtection = true
                        }
                    }
                ))
            } header: {
                Text("保护模式")
            } footer: {
                Text("开启后会用主密码加密本机的 TOTP 秘钥，每次打开 Rotor 需要解锁，并在空闲后自动锁定。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if vault.protectionEnabled {
                Section {
                    Picker("空闲自动锁定", selection: $settings.autoLockMinutes) {
                        ForEach(autoLockOptions, id: \.0) { opt in
                            Text(opt.1).tag(opt.0)
                        }
                    }
                } header: {
                    Text("自动锁定")
                } footer: {
                    Text("空闲指定时间后要求重新输入主密码。键盘、鼠标、滚轮动作都算活动。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("修改主密码…") { showingChangePassword = true }
                    Button("立即锁定") { vault.lock() }
                } header: {
                    Text("主密码")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundStyle(.primary)
            Text("Rotor")
                .font(.system(size: 18, weight: .semibold))
            Text("Desktop-first 的开源 2FA 客户端")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("版本 1.0.0 (MVP)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
