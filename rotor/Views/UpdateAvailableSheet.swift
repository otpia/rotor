import AppKit
import SwiftUI

struct UpdateAvailableSheet: View {
    let release: UpdateChecker.Release

    @Environment(\.dismiss) private var dismiss
    @State private var checker = UpdateChecker.shared
    @State private var settings = SettingsStore.shared
    @State private var phase: Phase = .idle
    @State private var errorMessage: String?

    private enum Phase { case idle, downloading, finished }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("发现新版本 \(release.version)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("当前版本 \(checker.currentVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let date = release.publishedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            ScrollView {
                Text(release.body.isEmpty ? "（此版本未提供发行说明）" : release.body)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2))
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button("跳过此版本") {
                    settings.skippedUpdateVersion = release.version
                    dismiss()
                }
                .disabled(phase == .downloading)

                Spacer()

                Button("查看页面") {
                    NSWorkspace.shared.open(release.htmlURL)
                }
                .disabled(phase == .downloading)

                Button {
                    if phase == .finished {
                        dismiss()
                    } else {
                        Task { await downloadAndOpen() }
                    }
                } label: {
                    switch phase {
                    case .idle:
                        Text(release.dmgURL != nil ? "下载并安装" : "前往下载")
                    case .downloading:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("下载中…")
                        }
                    case .finished:
                        Text("完成")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(phase == .downloading)
            }
        }
        .padding(16)
        .frame(width: 480)
        .onDisappear {
            // Clear the prompt source so it doesn't re-fire across windows
            checker.pendingPrompt = nil
        }
    }

    private func downloadAndOpen() async {
        errorMessage = nil
        guard release.dmgURL != nil else {
            NSWorkspace.shared.open(release.htmlURL)
            phase = .finished
            return
        }
        phase = .downloading
        do {
            let dmg = try await checker.download(release)
            // Reveal the DMG in Finder and mount it; user drags Rotor.app into /Applications
            NSWorkspace.shared.open(dmg)
            phase = .finished
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }
}
