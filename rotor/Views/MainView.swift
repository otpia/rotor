import AppKit
import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [AccountModel]

    @State private var query: String = ""
    @State private var presenting: FormPresentation?
    @State private var settings = SettingsStore.shared
    @State private var vault = VaultManager.shared

    // Reorder mode: use List + .onMove for native drag and drop
    @State private var reorderMode: Bool = false

    private enum FormPresentation: Identifiable {
        case new
        case edit(AccountModel)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let a): return a.id.uuidString
            }
        }
    }

    private var filtered: [AccountModel] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return accounts }
        return accounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(q) ||
            $0.label.localizedCaseInsensitiveContains(q) ||
            $0.group.localizedCaseInsensitiveContains(q)
        }
    }

    private var sectioned: [(group: String, items: [AccountModel])] {
        let sorted: [AccountModel]
        switch settings.sortMode {
        case .manual:
            sorted = filtered.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
        case .alphabetical:
            sorted = filtered.sorted {
                $0.issuer.localizedCaseInsensitiveCompare($1.issuer) == .orderedAscending
            }
        case .recent:
            sorted = filtered.sorted { $0.createdAt > $1.createdAt }
        }

        var buckets: [String: [AccountModel]] = [:]
        var order: [String] = []
        for account in sorted {
            if buckets[account.group] == nil {
                buckets[account.group] = []
                order.append(account.group)
            }
            buckets[account.group]?.append(account)
        }
        order.sort { lhs, rhs in
            if lhs.isEmpty && !rhs.isEmpty { return true }
            if !lhs.isEmpty && rhs.isEmpty { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private var hasAnyNamedGroup: Bool {
        accounts.contains { !$0.group.isEmpty }
    }

    // In reorder mode, use a flat sorted list of all accounts: by group + sortOrder
    private var flatForReorder: [AccountModel] {
        accounts.sorted { lhs, rhs in
            if lhs.group != rhs.group {
                if lhs.group.isEmpty { return true }
                if rhs.group.isEmpty { return false }
                return lhs.group.localizedCaseInsensitiveCompare(rhs.group) == .orderedAscending
            }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        Group {
            switch vault.state {
            case .locked:
                LockScreenView()
            case .unlocked:
                unlockedContent
                    .onAppear {
                        DemoSeed.seedIfEmpty(context: context)
                    }
            }
        }
        .frame(minWidth: 480, minHeight: 600)
        .background(Color.rotorBackground)
        .sheet(item: $presenting) { presentation in
            switch presentation {
            case .new:
                AccountFormView(mode: .new)
                    .environment(\.modelContext, context)
            case .edit(let account):
                AccountFormView(mode: .edit(account))
                    .environment(\.modelContext, context)
            }
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 12)

            if reorderMode {
                reorderList
            } else {
                normalList
            }
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if reorderMode {
            HStack(spacing: 12) {
                Text("重新排序")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("按住卡片拖动，完成后点右侧")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        reorderMode = false
                    }
                } label: {
                    Text("完成")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.rotorPrimary))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("完成排序")
            }
        } else {
            HStack(spacing: 12) {
                SearchBar(text: $query)
                Menu {
                    Picker(selection: $settings.sortMode) {
                        ForEach(AccountSortMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("排序方式")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        reorderMode = true
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("进入重排模式")
                Button {
                    presenting = .new
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.rotorPrimary))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.command])
                .help("添加账户 (⌘N)")
            }
        }
    }

    // MARK: - Normal mode (view TOTP codes)

    @ViewBuilder
    private var normalList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sectioned, id: \.group) { section in
                    if hasAnyNamedGroup {
                        Text(section.group.isEmpty ? "未分组" : section.group)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, section.group == sectioned.first?.group ? 0 : 8)
                            .padding(.leading, 4)
                    }
                    ForEach(section.items) { account in
                        AccountCard(account: account)
                            .contextMenu {
                                Button {
                                    presenting = .edit(account)
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    delete(account)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }

                if accounts.isEmpty {
                    ContentUnavailableView(
                        "还没有账户",
                        systemImage: "lock.shield",
                        description: Text("点击右上角「+」添加第一个 TOTP 账户")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的账户",
                        systemImage: "magnifyingglass",
                        description: Text("换一个关键词试试")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Reorder mode (visfitness/Reorderable provides the GA-style feel)

    @ViewBuilder
    private var reorderList: some View {
        // ReorderableVStack is built on DragGesture for immediate response; isDragged drives scale-up + shadow for the "card lifted" effect
        // ScrollView.autoScrollOnEdges() handles auto-scroll when dragging near the edges
        ScrollView(.vertical, showsIndicators: false) {
            // ReorderableVStack uses VStack(spacing: 0) internally; row spacing is provided by per-row padding
            ReorderableVStack(flatForReorder, onMove: handleMove) { account, isDragged in
                ReorderRow(account: account, isDragging: isDragged)
                    .scaleEffect(isDragged ? 1.04 : 1)
                    .padding(.bottom, 8)
                    .animation(.easeOut(duration: 0.15), value: isDragged)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .autoScrollOnEdges()
    }

    private func handleMove(from source: Int, to destination: Int) {
        var arr = flatForReorder
        // Reorderable's onMove uses single-index (from, to) semantics; per README, add +1 when to > from
        let target = destination > source ? destination + 1 : destination
        arr.move(fromOffsets: IndexSet(integer: source), toOffset: target)

        // When crossing groups, the dragged item's group follows its neighbor
        if let movedIdx = arr.firstIndex(where: { $0.id == flatForReorder[source].id }) {
            let moved = arr[movedIdx]
            let neighbor: AccountModel? = movedIdx > 0
                ? arr[movedIdx - 1]
                : (movedIdx + 1 < arr.count ? arr[movedIdx + 1] : nil)
            if let neighbor, moved.group != neighbor.group {
                moved.group = neighbor.group
            }
        }

        // Renumber within each group according to the new order
        var perGroupCounter: [String: Int] = [:]
        for acc in arr {
            let n = perGroupCounter[acc.group] ?? 0
            acc.sortOrder = n
            perGroupCounter[acc.group] = n + 1
        }
        try? context.save()

        if settings.sortMode != .manual {
            settings.sortMode = .manual
        }
    }

    // MARK: - Data operations

    private func delete(_ account: AccountModel) {
        context.delete(account)
        try? context.save()
    }
}
