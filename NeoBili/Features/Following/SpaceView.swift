import SwiftUI

/// UP 主空间页。头图 + 名片在上，下面用分段控件在「投稿」和「动态」之间切换。
///
/// 排版参考 B 站客户端的空间页，但只保留看内容需要的部分：充电、大航海、
/// 特别关注这些和播放无关的入口都不做。
struct SpaceView: View {
    let up: FollowedUp

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @State private var viewModel: SpaceViewModel
    @State private var tab: Tab = .videos
    @State private var detailEntry: DynamicEntry?

    private enum Tab: String, CaseIterable, Identifiable {
        case videos = "投稿"
        case dynamics = "动态"

        var id: String { rawValue }
    }

    init(up: FollowedUp) {
        self.up = up
        _viewModel = State(initialValue: SpaceViewModel(mid: up.mid))
    }

    var body: some View {
        // 两栏做成分页，左右滑动就能换——分段控件只是另一种切换方式。
        TabView(selection: $tab) {
            page(for: .videos).tag(Tab.videos)
            page(for: .dynamics).tag(Tab.dynamics)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(viewModel.card?.name ?? up.uname)
        .navigationBarTitleDisplayMode(.inline)
        // 顶栏改成实底。半透明时内容从导航栏背后滑过去，会和吸顶的分段控件
        // 叠成两层深浅不一的模糊，看起来像没对齐。
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .secondarySystemGroupedBackground), for: .navigationBar)
        // 进了 UP 主页就把底部标签栏收起来，整屏都留给他的内容。
        .toolbarVisibility(.hidden, for: .tabBar)
        .task { await viewModel.loadInitial() }
        .task(id: tab) {
            // 切到动态那一栏才去加载它，进页面时不白跑一次请求。
            if tab == .dynamics {
                await viewModel.dynamics.loadInitial()
            }
        }
        .onAppear { OrientationController.enterPortrait() }
        .navigationDestination(item: $detailEntry) { entry in
            DynamicDetailView(entry: entry)
        }
    }

    /// 一栏的内容。头部跟着一起滑，分段控件吸在顶上。
    private func page(for tab: Tab) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                header

                Section {
                    switch tab {
                    case .videos: videoList
                    case .dynamics: dynamicList
                    }
                } header: {
                    tabPicker
                }
            }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            banner

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(viewModel.card?.name ?? up.uname)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if let level = viewModel.card?.level, level > 0 {
                    Text("LV\(level)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                if viewModel.card?.isVIP == true {
                    Text("大会员")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.pink, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Spacer(minLength: 0)

                followButton
            }

            statsRow

            if let sign = viewModel.card?.sign, !sign.isEmpty {
                Text(sign)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, SpaceHeaderLayout.horizontalInset)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    /// 头图。头像压在它的左下角，一半探出到下面的信息区里。
    private var banner: some View {
        Group {
            if let url = viewModel.card?.secureBannerURL {
                CoverThumbnail(url: url, aspectRatio: SpaceHeaderLayout.bannerAspectRatio)
            } else {
                // 没设置过头图（或者名片还没回来）时给一层渐变，
                // 比让图片控件显示「图裂了」的占位好看得多。
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(SpaceHeaderLayout.bannerAspectRatio, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            BiliImage(url: viewModel.card?.secureAvatarURL ?? up.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: SpaceHeaderLayout.avatarSize, height: SpaceHeaderLayout.avatarSize)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 3)
                }
                // 头像不要顶在屏幕左缘，和下面的名字、签名对齐。
                .padding(.leading, SpaceHeaderLayout.horizontalInset)
                .offset(y: SpaceHeaderLayout.avatarSize / 2)
        }
        // 头图本身画到屏幕两边，所以要把外层的左右留白抵消掉。
        .padding(.horizontal, -SpaceHeaderLayout.horizontalInset)
        // 给探出来的那半个头像让出高度。
        .padding(.bottom, SpaceHeaderLayout.avatarSize / 2 + 8)
    }

    private var statsRow: some View {
        HStack(spacing: 22) {
            stat(count: viewModel.card?.follower, label: "粉丝")
            stat(count: viewModel.card?.followingCount, label: "关注")
            stat(count: viewModel.card?.likeCount, label: "获赞")
            Spacer(minLength: 0)
        }
    }

    private func stat(count: Int?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(count.map(\.biliCountText) ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var followButton: some View {
        Button {
            Task {
                if let message = await viewModel.toggleFollow(isLoggedIn: account.isLoggedIn) {
                    feedback.show(message)
                }
            }
        } label: {
            Text(viewModel.isFollowing ? "已关注" : "关注")
                .font(.footnote.weight(.medium))
                .frame(minWidth: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isFollowing ? Color(uiColor: .systemFill) : .accentColor)
        .foregroundStyle(viewModel.isFollowing ? Color.primary : Color.white)
        .controlSize(.small)
    }

    private var tabPicker: some View {
        Picker("内容", selection: $tab) {
            ForEach(Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, SpaceHeaderLayout.horizontalInset)
        .padding(.vertical, 8)
        // 吸顶的这条要实底，卡片从它背后滑过去时不能透出来。
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - 投稿

    @ViewBuilder
    private var videoList: some View {
        if viewModel.isLoadingVideos, viewModel.videos.isEmpty {
            ProgressView().padding(.vertical, 40)
        } else if let message = viewModel.videosError, viewModel.videos.isEmpty {
            ContentUnavailableView("加载失败", systemImage: "wifi.slash", description: Text(message))
                .padding(.vertical, 20)
        } else if viewModel.videos.isEmpty {
            ContentUnavailableView("没有投稿", systemImage: "video.slash", description: Text("这位 UP 主还没有公开的视频稿件。"))
                .padding(.vertical, 20)
        } else {
            ForEach(viewModel.videos) { video in
                Button {
                    nowPlaying.open(
                        VideoDetailRoute(
                            bvid: video.bvid,
                            cover: video.pic,
                            title: video.title,
                            artist: video.author
                        ),
                        from: video.bvid
                    )
                } label: {
                    VideoListCard(
                        coverURL: URL.biliSecure(video.pic),
                        title: video.title,
                        // 整页都是同一个 UP 的稿件，作者名那一行改放发布时间更有用。
                        author: video.created > 0 ? video.created.biliRelativeTimeText : video.author,
                        playCount: video.play,
                        durationText: video.length
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
                }
                .videoTransitionSource(video.bvid, in: videoTransition)
                .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                .task { await viewModel.loadMoreVideosIfNeeded(current: video) }
                // 空间投稿列表里没有 cid，预取要先取一次详情再取播放地址。
                .task { await VideoPreparationCache.shared.prefetch(bvid: video.bvid) }
            }

            if viewModel.isLoadingMoreVideos {
                ProgressView().padding()
            }
        }
    }

    // MARK: - 动态

    @ViewBuilder
    private var dynamicList: some View {
        let feed = viewModel.dynamics

        if feed.isLoading, feed.entries.isEmpty {
            ProgressView().padding(.vertical, 40)
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView("加载失败", systemImage: "wifi.slash", description: Text(message))
                .padding(.vertical, 20)
        } else if feed.entries.isEmpty {
            ContentUnavailableView("还没有动态", systemImage: "bell.slash", description: Text("这位 UP 主还没有发过动态。"))
                .padding(.vertical, 20)
        } else {
            ForEach(feed.entries) { entry in
                DynamicCard(
                    entry: entry,
                    isLiked: feed.isLiked(entry),
                    likeCount: feed.likeCount(entry),
                    onOpenVideo: { open(entry) },
                    // 已经在这个 UP 的空间里了，头像不再是入口。
                    onOpenAuthor: nil,
                    onLike: { like(entry) },
                    onOpenDetail: { detailEntry = entry }
                )
                .contextMenu {
                    if let video = entry.video {
                        WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
                    }
                }
                .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
                .task { await feed.loadMoreIfNeeded(current: entry) }
                .task {
                    if let video = entry.video {
                        await VideoPreparationCache.shared.prefetch(bvid: video.bvid)
                    }
                }
            }

            if feed.isLoadingMore {
                ProgressView().padding()
            }
        }
    }

    private func open(_ entry: DynamicEntry) {
        guard let video = entry.video else { return }
        nowPlaying.open(
            VideoDetailRoute(
                bvid: video.bvid,
                cover: video.cover,
                title: video.title,
                artist: video.authorName
            ),
            from: video.bvid
        )
    }

    private func like(_ entry: DynamicEntry) {
        Task {
            if let message = await viewModel.dynamics.toggleLike(entry, isLoggedIn: account.isLoggedIn) {
                feedback.show(message)
            }
        }
    }
}

/// UP 主页头部的尺寸。
enum SpaceHeaderLayout {
    /// 头部内容与屏幕左右边缘的距离。
    static let horizontalInset: CGFloat = 16
    /// 头像直径。
    static let avatarSize: CGFloat = 72
    /// 头图的宽高比。B 站的空间头图本身就是这个比例。
    static let bannerAspectRatio: CGFloat = 3.0
}

#Preview {
    NavigationStack {
        SpaceView(up: FollowedUp(mid: 946974, uname: "影视飓风", face: "", hasUpdate: true))
            .environment(NowPlayingStore())
            .environment(AccountStore())
            .environment(ActionFeedback())
    }
}
