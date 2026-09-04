import SwiftUI

struct HomeView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @State private var viewModel = HomeViewModel()
    private static let topAnchor = "home-feed-top"

    private let columns = [
        GridItem(.flexible(), spacing: HomeCardLayout.columnSpacing),
        GridItem(.flexible(), spacing: HomeCardLayout.columnSpacing)
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        // 这是一个看不见的定位点。“上次看到这里”卡片被点击时，页面会回到这里再刷新。
                        Color.clear
                            .frame(height: 0)
                            .id(Self.topAnchor)

                        LazyVGrid(columns: columns, spacing: HomeCardLayout.rowSpacing) {
                            ForEach(viewModel.feedItems) { item in
                                switch item {
                                case .video(let video):
                                    // 推荐卡片自带 cid，直接交给详情页，省掉一次串行的详情请求。
                                    Button {
                                        nowPlaying.open(
                                            VideoDetailRoute(
                                                bvid: video.bvid,
                                                cid: video.cid,
                                                cover: video.pic,
                                                title: video.title,
                                                artist: video.owner.name
                                            ),
                                            from: video.bvid
                                        )
                                    } label: {
                                        VideoCard(video: video)
                                            .frame(height: HomeCardLayout.cardHeight(for: geometry.size.width))
                                    }
                                    .buttonStyle(.plain)
                                    .videoTransitionSource(video.bvid, in: videoTransition)
                                    .task {
                                        await viewModel.loadMoreIfNeeded(current: video)
                                    }
                                    // 卡片出现在屏幕上就先把播放地址取回来，点开时通常已经有结果了。
                                    // 分成两个 .task 是为了不让预取挡住上面的翻页请求。
                                    .task {
                                        await VideoPreparationCache.shared.prefetch(
                                            bvid: video.bvid,
                                            cid: video.cid
                                        )
                                    }

                                case .lastSeen:
                                    Button {
                                        Task {
                                            // 与 PiliPlus 一致：点击提示卡先回到顶部，再请求一批新推荐。
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                proxy.scrollTo(Self.topAnchor, anchor: .top)
                                            }
                                            await viewModel.refresh()
                                        }
                                    } label: {
                                        LastSeenCard()
                                            .frame(height: HomeCardLayout.cardHeight(for: geometry.size.width))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, HomeCardLayout.horizontalInset)
                        .padding(.vertical, HomeCardLayout.verticalInset)

                        // 下拉刷新已有系统顶部转圈，只有加载下一页时才在列表底部再显示进度。
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding()
                        }
                    }
                    // 对应 PiliPlus 的 AlwaysScrollableScrollPhysics：即使卡片不足一屏，也允许向下拉动刷新。
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .refreshable { await viewModel.refresh() }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            // 不显示“推荐”标题栏：卡片从屏幕顶部安全区下方直接开始，不再空出一整行标题高度。
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task { await viewModel.loadInitial() }
            // 登录/退出后同一套推荐接口在服务端会切到个性化/通用推流，
            // 这里保留旧内容、后台换成新批次，跟 PiliPlus 的行为一致。
            .onChange(of: account.profile?.mid) {
                Task { await viewModel.refresh() }
            }
            .onAppear {
                // Popping back here always restores the app's portrait lock.
                OrientationController.enterPortrait()
            }
            .overlay {
                if viewModel.isLoading, viewModel.videos.isEmpty {
                    ProgressView("正在加载推荐…")
                } else if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "wifi.slash",
                        description: Text(message)
                    )
                }
            }
        }
    }
}

/// 首页双列卡片的尺寸参数都在这里。提示卡和视频卡共同使用同一个高度计算公式。
private enum HomeCardLayout {
    /// 页面左右留白。
    static let horizontalInset: CGFloat = 8
    /// 左右两列之间的距离。
    static let columnSpacing: CGFloat = 8
    /// 上下两行之间的距离。
    static let rowSpacing: CGFloat = 10
    /// 网格顶部和底部的留白。
    static let verticalInset: CGFloat = 10
    /// 推荐封面保持 4:3。
    static let coverAspectRatio: CGFloat = 4.0 / 3.0
    /// 标题和 UP 主所在白色区域的固定高度。
    static let detailsHeight: CGFloat = 81

    /// 先根据屏幕宽度算出单列宽度，再加上 4:3 封面高度和文字区高度。
    static func cardHeight(for pageWidth: CGFloat) -> CGFloat {
        let availableWidth = max(0, pageWidth - horizontalInset * 2 - columnSpacing)
        let cardWidth = availableWidth / 2
        return cardWidth / coverAspectRatio + detailsHeight
    }
}

/// 分隔本次刷新和上一次内容的提示卡，外观占一个普通视频卡的位置。
private struct LastSeenCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.title3.weight(.medium))

            Text("上次看到这里\n点击刷新")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        // 外层会传入与视频卡完全相同的高度，这里只负责把背景铺满。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel("上次看到这里，点击刷新")
    }
}

private struct VideoCard: View {
    let video: VideoSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoCoverThumbnail(
                url: video.secureCoverURL,
                duration: video.formattedDuration,
                playCount: video.stat.view,
                aspectRatio: HomeCardLayout.coverAspectRatio
            )

            VStack(alignment: .leading, spacing: 7) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    BiliImage(url: video.secureAvatarURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())

                    Text(video.owner.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(height: HomeCardLayout.detailsHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

#Preview {
    HomeView()
        .environment(NowPlayingStore())
        .environment(AccountStore())
}
