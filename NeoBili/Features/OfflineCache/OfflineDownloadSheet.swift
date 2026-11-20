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

    private var scopeSelection: Binding<Bool> {
        Binding(
            get: { model.collectionSelected },
            set: { value in
                model.collectionSelected = value
                model.applyScope()
                Task { await model.changeScope() }
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    qualityPicker
                    if model.hasCollection {
                        Picker("缓存范围", selection: scopeSelection) {
                            Text("当前视频").tag(false)
                            Text("UP 主合集").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    HStack {
                        Text("选择缓存内容").font(.app(.subheadline, weight: .semibold))
                        Spacer()
                        Button(model.selected.count == model.videos.count && !model.videos.isEmpty ? "取消全选" : "全选") {
                            model.selected = model.selected.count == model.videos.count ? [] : Set(model.videos.map(\.id))
                        }
                        .font(.app(.subheadline))
                        .foregroundStyle(accent)
                        .disabled(model.videos.isEmpty)
                    }
                    if let message = model.duplicateMessage(in: cache.snapshot) {
                        Label(message, systemImage: "checkmark.circle").font(.app(.footnote)).foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        HStack(spacing: 12) {
                            Text(error).font(.app(.footnote)).foregroundStyle(.secondary)
                            Spacer()
                            Button("重新加载") {
                                Task { if model.collectionSelected { await model.changeScope() } else { await model.load() } }
                            }
                            .font(.app(.footnote))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if model.isLoading && model.videos.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                        } else {
                            ForEach(model.videos) { video in
                                Button {
                                    if !model.selected.insert(video.id).inserted { model.selected.remove(video.id) }
                                } label: {
                                    VideoListCard(
                                        coverURL: video.cover,
                                        title: video.displayTitle,
                                        author: subtitle(video),
                                        playCount: -1,
                                        durationText: OfflineCacheStyle.duration(video.duration)
                                    )
                                }
                                .buttonStyle(.plain)
                                .videoPickerSelection(model.selected.contains(video.id))
                                .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                                .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                                .id(video.id)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .videoPickerInitialPosition(target: model.currentVideoID)
                .id(model.collectionSelected)
            }
            .background(OfflineCacheStyle.background)
            .leftEdgeTapDeadZone()
            .navigationTitle("缓存视频").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.foregroundStyle(accent) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { confirmationBar }
            .confirmationDialog("替换已有缓存画质？", isPresented: $confirmsReplacement, titleVisibility: .visible) {
                Button("下载并替换") { submit(replace: true) }
                Button("取消", role: .cancel) {}
            }
        }
        .task { cache.connect(); await model.load() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .videoCardAnimationSource(.collection)
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        var parts: [String] = []
        if video.id == model.currentVideoID {
            parts.append(String(localized: "当前视频"))
        } else if !video.author.isEmpty {
            parts.append(video.author)
        }
        if let entry = (cache.snapshot.completed + cache.snapshot.tasks).first(where: { $0.id == video.id }) {
            parts.append("\(entry.state.title) · \(PlaybackQuality.videoTitle(entry.quality))")
        }
        return parts.joined(separator: " · ")
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
