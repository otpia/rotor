import SwiftData
import SwiftUI

// Menu bar popover: compact view that shows only the first N entries (CLAUDE.md §4.1 caps it at 10)
struct PopoverView: View {
    @Query(sort: [SortDescriptor(\AccountModel.sortOrder), SortDescriptor(\AccountModel.createdAt)])
    private var accounts: [AccountModel]

    @Environment(\.openWindow) private var openWindow
    @State private var settings = SettingsStore.shared
    @State private var vault = VaultManager.shared

    var limit: Int = 10

    private var visible: [AccountModel] { Array(accounts.prefix(limit)) }

    var body: some View {
        Group {
            if vault.state == .unlocked {
                unlockedBody
            } else {
                lockedPlaceholder
            }
        }
    }

    @ViewBuilder
    private var lockedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.rotorPrimary)
            Text("Rotor 已锁定")
                .font(.system(size: 13, weight: .semibold))
            Text("请在主窗口输入主密码解锁")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("打开主窗口") {
                showMainWindow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(width: 340, height: 320)
        .background(Color.rotorBackground)
        .onReceive(NotificationCenter.default.publisher(for: .rotorShowMainWindow)) { _ in
            showMainWindow()
        }
    }

    @ViewBuilder
    private var unlockedBody: some View {
        VStack(spacing: 0) {
            HStack {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                Text("Rotor")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    showMainWindow()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("打开主窗口")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(visible) { account in
                        AccountCard(account: account, compact: true)
                    }
                    if visible.isEmpty {
                        Text("还没有账户")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(24)
                    }
                }
                .padding(12)
            }

            if accounts.count > limit {
                Divider()
                HStack {
                    Text("显示前 \(limit) 个，共 \(accounts.count) 个")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 340, height: 520)
        .background(Color.rotorBackground)
        .background(
            WindowAccessor(
                level: settings.popoverPinned ? .floating : .normal,
                sharingType: settings.screenCaptureBlocked ? .none : .readOnly
            )
        )
        // The status bar right-click menu's "Show main window" item and a second Dock click both post this notification
        .onReceive(NotificationCenter.default.publisher(for: .rotorShowMainWindow)) { _ in
            showMainWindow()
        }
    }

    private func showMainWindow() {
        // Restore Dock + ⌘Tab presence before activating; if we stayed in
        // .accessory the main window may not come to the front reliably
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
