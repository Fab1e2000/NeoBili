import SwiftUI
import NeoBiliDomain

struct OfflineDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemeColor) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.offlineCacheNavigation) private var cacheNavigation
    @State private var model: OfflineSelectionModel
    private let cache: OfflineCacheStore
    @State private var confirmsReplacement = false

    init(bvid: String, cid: Int?, services: ApplicationServices = .live, cache: OfflineCacheStore = .shared) {
        _model = State(initialValue: OfflineSelectionModel(bvid: bvid, cid: cid, services: services))
        self.cache = cache
    }

    private var cannotSubmit: Bool {
        model.isLoading || model.isSubmitting || model.quality == nil || model.selectedVideos.isEmpty
            || model.duplicateMessage(in: cache.snapshot) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let video = model.videos.first { summary(video) }
                    qualityPicker
                    if model.hasCollection {
                        Picker("缓存范围", selection: $model.collectionSelected) {
                            Text("当前视频").tag(false)
                            Text("UP 主合集").tag(true)
                        }.pickerStyle(.segmented).disabled(model.isLoading)
                    }
                    selection
                    if model.isLoading { ProgressView("正在准备可缓存内容").frame(maxWidth: .infinity) }
                    if let message = model.duplicateMessage(in: cache.snapshot) {
                        Label(message, systemImage: "checkmark.circle").font(.app(.footnote)).foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error).font(.app(.footnote)).foregroundStyle(.secondary)
                            Button("重新加载") { Task { if model.collectionSelected { await model.changeScope() } else { await model.load() } } }
                        }
                    }
                }
                .padding(20)
            }
            .background(OfflineCacheStyle.background)
            .navigationTitle("缓存视频").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.foregroundStyle(accent) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { confirmationBar }
            .confirmationDialog("替换已有缓存画质？", isPresented: $confirmsReplacement, titleVisibility: .visible) {
                Button("下载并替换") { submit(replace: true) }
                Button("取消", role: .cancel) {}
            } message: { Text("新版本完整下载后替换旧版。下载期间仍可观看原有缓存。") }
        }
        .task { cache.connect(); await model.load() }
        .onChange(of: model.collectionSelected) { Task { await model.changeScope() } }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func summary(_ video: OfflineVideo) -> some View {
        HStack(spacing: 12) {
            OfflineCover(remoteURL: video.cover, width: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.collectionSelected ? video.groupTitle : video.title)
                    .font(.app(.subheadline, weight: .medium)).lineLimit(2)
                Text("\(video.author) · \(model.videos.count) 项")
                    .font(.app(.caption)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12).background(OfflineCacheStyle.card, in: RoundedRectangle(cornerRadius: OfflineCacheStyle.radius))
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("缓存画质").font(.app(.subheadline, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 130 : 85), spacing: 8)], spacing: 8) {
                ForEach(model.qualities, id: \.self) { quality in
                    Button { model.quality = quality } label: {
                        Text(PlaybackQuality.videoTitle(quality)).font(.app(.subheadline))
                            .foregroundStyle(model.quality == quality ? accent : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 42).padding(.horizontal, 4)
                            .background(model.quality == quality ? accent.opacity(0.08) : OfflineCacheStyle.card,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.quality == quality ? accent : .clear))
                    }.buttonStyle(.plain).disabled(model.isLoading)
                        .accessibilityAddTraits(model.quality == quality ? .isSelected : [])
                }
            }
            if model.quality == nil && !model.isLoading { Text("请选择可用画质").font(.app(.footnote)).foregroundStyle(accent) }
            Text("同时保存弹幕和全部字幕 · 默认仅 Wi-Fi")
                .font(.app(.caption)).foregroundStyle(.secondary)
        }
    }

    private var selection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("选择缓存内容").font(.app(.subheadline, weight: .semibold))
                Spacer()
                Button(model.selected.count == model.videos.count ? "取消全选" : "全选") {
                    model.selected = model.selected.count == model.videos.count ? [] : Set(model.videos.map(\.id))
                }.font(.app(.subheadline)).foregroundStyle(accent).disabled(model.isLoading || model.videos.isEmpty)
            }
            LazyVStack(spacing: 8) {
                ForEach(model.videos) { video in
                    OfflineEpisodeRow(number: (model.videos.firstIndex(where: { $0.id == video.id }) ?? 0) + 1,
                        title: video.displayTitle, subtitle: subtitle(video), selected: model.selected.contains(video.id),
                        current: video.bvid == model.bvid && video.cid == model.cid) {
                            if !model.selected.insert(video.id).inserted { model.selected.remove(video.id) }
                        }.disabled(model.isLoading)
                }
            }
        }
    }

    private var confirmationBar: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("已选 \(model.selectedVideos.count) 项")
                    Spacer()
                    selectedDuration
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选 \(model.selectedVideos.count) 项")
                    selectedDuration
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.app(.caption)).foregroundStyle(.secondary)
            Button {
                if model.needsReplacement(in: cache.snapshot) { confirmsReplacement = true }
                else { submit(replace: false) }
            } label: {
                Label(model.isSubmitting ? "正在添加" : "开始缓存", systemImage: "arrow.down.to.line")
                    .font(.app(.subheadline, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(.white).background(accent.opacity(cannotSubmit ? 0.45 : 1), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(cannotSubmit)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10).background(OfflineCacheStyle.card)
    }

    private var selectedDuration: some View {
        Text("总时长 \(OfflineCacheStyle.duration(model.selectedVideos.reduce(0) { $0 + $1.duration }))")
    }
    private func subtitle(_ video: OfflineVideo) -> String {
        var value = OfflineCacheStyle.duration(video.duration)
        if video.bvid == model.bvid && video.cid == model.cid { value += " · 当前" }
        if let entry = (cache.snapshot.completed + cache.snapshot.tasks).first(where: { $0.id == video.id }) {
            value += " · \(entry.state.title) · \(PlaybackQuality.videoTitle(entry.quality))"
        }
        return value
    }
    private func submit(replace: Bool) {
        Task {
            if await model.submit(replace: replace) {
                dismiss()
                cacheNavigation?.openDownloads()
            }
        }
    }
}
