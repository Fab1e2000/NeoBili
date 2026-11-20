import SwiftUI
import NeoBiliDomain

struct OfflineCacheView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(\.applicationServices) private var services
    @Environment(\.appThemeColor) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimations = CardAnimationSettings.defaultValue
    @Bindable var cache: OfflineCacheStore
    private let groupID: String?
    @State private var showsDownloads: Bool
    @State private var selected: Set<String> = []
    @State private var isEditing = false
    @State private var deletion: [OfflineCacheEntry] = []
    @State private var confirmsDeletion = false
    @State private var changingQuality: OfflineCacheEntry?
    @State private var cellularTask: OfflineCacheEntry?

    init(cache: OfflineCacheStore = .shared, groupID: String? = nil, showsDownloads: Bool = false) {
        self.cache = cache; self.groupID = groupID
        _showsDownloads = State(initialValue: showsDownloads)
    }

    private var completed: [OfflineCacheEntry] {
        groupID.map { cache.entries(in: $0) } ?? cache.completed
    }
    private var title: String { completed.first.map { groupID == nil ? "离线缓存" : $0.video.groupTitle } ?? "离线缓存" }
    private var selectedEntries: [OfflineCacheEntry] { completed.filter { selected.contains($0.id) } }
    private var animatesRemoval: Bool { cardAnimations && !reduceMotion }

    private func grouped(_ entries: [OfflineCacheEntry]) -> [(id: String, entries: [OfflineCacheEntry])] {
        Dictionary(grouping: entries, by: { $0.video.groupID })
            .map { (id: $0.key, entries: $0.value.sorted { $0.video.order < $1.video.order }) }
            .sorted { ($0.entries.map(\.createdAt).max() ?? .distantPast) > ($1.entries.map(\.createdAt).max() ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if groupID == nil { cachePicker }
                if let message = cache.storageError { Text(message).font(.app(.footnote)).foregroundStyle(.red) }
                if showsDownloads { downloads }
                else { library }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(OfflineCacheStyle.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(groupID == nil ? .large : .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !showsDownloads {
                    Button(isEditing ? "完成" : "管理") { isEditing.toggle(); selected = [] }
                        .foregroundStyle(accent).disabled(completed.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing && !showsDownloads { deletionBar }
        }
        .onChange(of: showsDownloads) { _, _ in isEditing = false; selected = [] }
        .confirmationDialog("删除缓存？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除 \(deletion.count) 项", role: .destructive, action: deleteConfirmed)
            Button("取消", role: .cancel) {}
        } message: { Text("将释放 \(Self.size(deletion.reduce(0) { $0 + $1.receivedBytes }))。") }
        .confirmationDialog("允许使用蜂窝网络？", isPresented: Binding(
            get: { cellularTask != nil }, set: { if !$0 { cellularTask = nil } }
        ), titleVisibility: .visible) {
            if let entry = cellularTask {
                Button("允许此任务") { cache.perform { [service = cache.service] in try await service.resume(entry.id, true) } }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("缓存操作失败", isPresented: Binding(get: { cache.errorMessage != nil }, set: { if !$0 { cache.errorMessage = nil } })) {
            Button("好") { cache.errorMessage = nil }
        } message: { Text(cache.errorMessage ?? "") }
        .sheet(item: $changingQuality) { entry in
            OfflineDownloadSheet(bvid: entry.video.bvid, cid: entry.video.cid, services: services, cache: cache).appTextSize()
        }
        .task { cache.connect() }
    }

    private var cachePicker: some View {
        Picker("缓存状态", selection: $showsDownloads) {
            Text("已缓存").tag(false)
            Text("下载中 \(cache.taskCount)").tag(true)
        }.pickerStyle(.segmented)
    }

    @ViewBuilder private var library: some View {
        if completed.isEmpty {
            ContentUnavailableView("暂无缓存", systemImage: "arrow.down.to.line")
        } else {
            let groups = groupID == nil ? grouped(completed) : []
            VStack(spacing: 12) {
                LazyVStack(spacing: 10) {
                    if groupID != nil {
                        ForEach(completed) { entry in
                            cachedItem([entry], isGroup: false)
                                .removalFillTransition()
                        }
                    } else {
                        ForEach(groups, id: \.id) { group in
                            cachedItem(group.entries, isGroup: group.entries.count > 1 || group.entries.first?.video.partTitle.isEmpty == false)
                                .removalFillTransition()
                        }
                    }
                }
                if groupID != nil && !isEditing {
                    Button("删除整组", role: .destructive) { askToDelete(completed) }.font(.app(.footnote))
                }
            }
            .removalFill(ids: groupID != nil ? completed.map(\.id) : groups.map(\.id),
                         enabled: animatesRemoval)
        }
    }

    @ViewBuilder private func cachedItem(_ entries: [OfflineCacheEntry], isGroup: Bool) -> some View {
        if let entry = entries.first {
            Group {
                if isGroup && !isEditing {
                    NavigationLink { OfflineCacheView(cache: cache, groupID: entry.video.groupID) } label: {
                        cachedLabel(entries, isGroup: true)
                    }
                } else {
                    Button {
                        if isEditing { toggleSelection(entries) } else { open(entry) }
                    } label: { cachedLabel(entries, isGroup: isGroup) }
                }
            }
            .buttonStyle(CardPressStyle(cornerRadius: OfflineCacheStyle.radius))
            .accessibilityLabel(isGroup ? entry.video.groupTitle : entry.video.displayTitle)
            .accessibilityValue(isEditing ? (entries.allSatisfy { selected.contains($0.id) } ? "已选择" : "未选择") : "\(entries.count) 项")
            .contextMenu {
                if !isGroup { Button("更换画质") { changingQuality = entry } }
                Button(isGroup ? "删除整组" : "删除", role: .destructive) { askToDelete(entries) }
            }
        }
    }

    private func cachedLabel(_ entries: [OfflineCacheEntry], isGroup: Bool) -> some View {
        let entry = entries[0]
        let allSelected = entries.allSatisfy { selected.contains($0.id) }
        return HStack(spacing: 12) {
            if isEditing {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(allSelected ? accent : .secondary)
            }
            OfflineCover(remoteURL: nil, localURL: cache.completedCovers[entry.generation],
                         badge: isGroup ? "\(entries.count) 集" : OfflineCacheStyle.duration(entry.video.duration),
                         width: isEditing ? 80 : 108)
            VStack(alignment: .leading, spacing: 6) {
                Text(isGroup ? entry.video.groupTitle : entry.video.displayTitle)
                    .font(.app(.subheadline, weight: .medium)).foregroundStyle(.primary).lineLimit(2)
                Text(entry.video.author).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                Text(isGroup ? "\(entries.count) 集 · \(Self.size(entries.reduce(0) { $0 + $1.receivedBytes }))"
                     : "\(PlaybackQuality.videoTitle(entry.quality)) · \(Self.size(entry.receivedBytes))")
                    .font(.app(.caption)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: OfflineCacheStyle.radius, style: .continuous)
            if allSelected && isEditing {
                shape.fill(OfflineCacheStyle.background)
                    .overlay { shape.fill(accent.opacity(0.1)) }
            } else {
                shape.fill(OfflineCacheStyle.card)
            }
        }
    }

    @ViewBuilder private var downloads: some View {
        if cache.tasks.isEmpty {
            ContentUnavailableView("暂无下载任务", systemImage: "arrow.down.circle")
        } else {
            let groups = grouped(cache.tasks)
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.id) { group in
                    Text(group.entries.first?.video.groupTitle ?? "")
                        .font(.app(.subheadline, weight: .semibold)).padding(.top, 2)
                    ForEach(group.entries) { entry in
                        OfflineDownloadCard(entry: entry, coverURL: cache.taskCovers[entry.generation],
                            speed: cache.speeds[entry.id] ?? 0,
                            toggle: {
                                cache.perform { [service = cache.service] in
                                    if entry.state.canSchedule { try await service.pause(entry.id) }
                                    else { try await service.resume(entry.id, false) }
                                }
                            }, allowCellular: { cellularTask = entry },
                            changeQuality: { changingQuality = entry },
                            cancel: { cache.perform { [service = cache.service] in try await service.cancel(entry.id) } })
                            .removalFillTransition()
                    }
                }
            }
            .removalFill(ids: groups.flatMap { $0.entries.map(\.id) }, enabled: animatesRemoval)
        }
    }

    private var deletionBar: some View {
        HStack {
            Button(selected.count == completed.count ? "取消全选" : "全选") {
                selected = selected.count == completed.count ? [] : Set(completed.map(\.id))
            }
            Spacer()
            Button("删除 \(selectedEntries.count) 项", role: .destructive) { askToDelete(selectedEntries) }
                .disabled(selectedEntries.isEmpty)
        }
        .font(.app(.subheadline, weight: .medium)).padding(20).background(OfflineCacheStyle.card)
    }

    private func toggleSelection(_ entries: [OfflineCacheEntry]) {
        let ids = Set(entries.map(\.id))
        if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
    }
    private func open(_ entry: OfflineCacheEntry) {
        Task {
            do { try await nowPlaying.openOffline(entry.id, service: cache.service, from: "offline-\(entry.id)") }
            catch { cache.errorMessage = error.localizedDescription }
        }
    }
    private func askToDelete(_ entries: [OfflineCacheEntry]) { deletion = entries; confirmsDeletion = true }
    private func deleteConfirmed() {
        let entries = deletion, ids = Set(entries.map(\.id))
        if let current = nowPlaying.offline, ids.contains(current.entry.id) { nowPlaying.close() }
        cache.perform { [service = cache.service] in try await service.delete(Array(ids)) }
        for entry in entries { nowPlaying.removeOfflineProgress(for: entry) }
        selected.subtract(ids)
    }
    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file) }
}

private struct OfflineDownloadCard: View {
    @Environment(\.appThemeColor) private var accent
    let entry: OfflineCacheEntry
    let coverURL: URL?
    let speed: Double
    let toggle: () -> Void
    let allowCellular: () -> Void
    let changeQuality: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                OfflineCover(remoteURL: entry.video.cover, localURL: coverURL, width: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.video.displayTitle).font(.app(.subheadline, weight: .medium)).lineLimit(2)
                    Text("\(PlaybackQuality.videoTitle(entry.quality)) · \(entry.state.title)")
                        .font(.app(.caption)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: toggle) {
                    Image(systemName: entry.state.canSchedule ? "pause.fill" : entry.state == .failed ? "arrow.clockwise" : "play.fill")
                        .font(.system(size: 12, weight: .semibold)).frame(width: 40, height: 40)
                        .overlay(Circle().stroke(accent.opacity(0.5), lineWidth: 1.5))
                }.foregroundStyle(accent)
                    .accessibilityLabel(entry.state.canSchedule ? "暂停" : entry.state == .failed ? "重试" : "继续")
            }
            if entry.state == .preparing { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
            else { ProgressView(value: entry.progress ?? 0).tint(accent) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    transferredSize
                    Spacer(minLength: 8)
                    transferSpeed
                }
                VStack(alignment: .leading, spacing: 4) {
                    transferredSize
                    transferSpeed
                }
            }.font(.app(.caption)).monospacedDigit()
            if let message = entry.message { Text(message).font(.app(.caption)).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actions }
                VStack(alignment: .leading, spacing: 12) { actions }
            }
            .font(.app(.caption)).buttonStyle(.plain)
        }
        .padding(14).background(OfflineCacheStyle.card, in: RoundedRectangle(cornerRadius: OfflineCacheStyle.radius))
    }

    private var transferredSize: some View {
        Text(OfflineCacheView.size(entry.receivedBytes) + (entry.expectedBytes > 0 ? " / " + OfflineCacheView.size(entry.expectedBytes) : ""))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var transferSpeed: some View {
        if speed > 0 { Text(OfflineCacheView.size(Int64(speed)) + "/s").foregroundStyle(accent) }
    }

    @ViewBuilder private var actions: some View {
        if !entry.allowsCellular { Button("使用蜂窝", systemImage: "antenna.radiowaves.left.and.right", action: allowCellular).foregroundStyle(accent) }
        Button("更换画质", action: changeQuality).foregroundStyle(.secondary)
        Button("取消下载", role: .destructive, action: cancel).foregroundStyle(.secondary)
    }
}
