import Foundation

@MainActor
@Observable
final class VideoDetailViewModel {
    let bvid: String
    private(set) var detail: VideoDetail?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// 官方相关视频推流。它和详情是两个独立的请求，谁先回来先显示谁，
    /// 所以相关视频不会被详情接口拖慢，反过来也一样。
    private(set) var related: [VideoSummary] = []
    private(set) var isLoadingRelated = false

    /// 稿件标签。加载失败只是少一行 chip，不影响页面其它部分。
    private(set) var tags: [VideoTag] = []
    /// 当前账号与这个稿件的关系。未登录、或者接口失败时为 nil，
    /// 此时五个操作按钮全部显示成未激活。
    private(set) var relation: VideoRelation?
    /// UP 主的粉丝数和投稿数。
    private(set) var ownerCard: MemberCard?

    /// 操作栏上的计数。
    ///
    /// `VideoDetail` 是不可变的值类型，而点赞、投币、收藏都要在请求发出前先把
    /// 数字改掉（乐观更新），所以这三个数单独镜像一份，详情回来时从 `stat` 播种。
    private(set) var likeCount = 0
    private(set) var coinCount = 0
    private(set) var favoriteCount = 0

    /// 操作结果提示。界面弹完就置回 nil。
    var actionMessage: String?

    /// 有请求正在飞的按钮，用来防连点。
    private var busyActions: Set<Action> = []

    private enum Action: Hashable {
        case like, dislike, coin, favorite, follow, triple
    }

    /// 已经三连过的稿件不再重复三连（硬币收不回来，重复投也没意义）。
    var hasTripled: Bool {
        guard let relation else { return false }
        return relation.isLiked && relation.isCoined && relation.isFavorited
    }

    init(bvid: String) {
        self.bvid = bvid
    }

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            // 搜索卡片如果已经预取过详情，这里会直接读取缓存，不再重复请求。
            let loaded = try await VideoPreparationCache.shared.detail(for: bvid)
            detail = loaded
            likeCount = loaded.stat.like
            coinCount = loaded.stat.coin
            favoriteCount = loaded.stat.favorite
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadRelated() async {
        guard related.isEmpty, !isLoadingRelated else { return }
        isLoadingRelated = true
        // 相关视频加载失败只是少一块内容，不该让整个视频页显示成错误页。
        related = (try? await BiliAPI.relatedVideos(bvid: bvid)) ?? []
        isLoadingRelated = false
    }

    /// 标签、互动状态、UP 主名片。
    ///
    /// 三者都要等详情拿到 aid / mid 才能发，但彼此之间没有依赖，所以并行发出，
    /// 各自失败只少一块内容——和 `loadRelated` 一样，不会把页面变成错误页。
    func loadExtras() async {
        guard let detail else { return }
        async let tags = try? BiliAPI.videoTags(aid: detail.aid)
        async let relation = try? BiliAPI.videoRelation(aid: detail.aid, bvid: detail.bvid)
        async let card = try? BiliAPI.memberCard(mid: detail.owner.mid)

        self.tags = await tags ?? []
        self.relation = await relation
        self.ownerCard = await card
    }

    // 写操作成功后**不要**再回读 `archive/relation`。
    //
    // 服务端的写入不是立刻可读的：刚点完踩就去查，多半还拿得到旧的 dislike=false，
    // 于是这份陈旧快照把刚做完的乐观更新整个盖回去——按钮闪一下就弹回未激活。
    // 更糟的是它盖的是**整个** relation 对象，所以下一个动作的回读又会把上一个
    // 动作的结果一起冲掉，几个按钮看起来就互相干扰：点踩不变色，点了投币之后
    // 点踩才变色（那时候那次回读终于读到了）。
    //
    // 接口返回成功就说明服务端已经接受了这次修改，本地的乐观值就是正确值，
    // 没有再问一遍的必要。真实状态在下次进入视频页时由 `loadExtras` 读取。

    // MARK: - 操作

    func toggleLike(isLoggedIn: Bool) async {
        guard let detail, checkReady(.like, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.like) }

        let wasLiked = relation?.isLiked ?? false
        let wasDisliked = relation?.isDisliked ?? false
        // 点赞和点踩互斥，界面上先按最终状态显示。
        apply(like: !wasLiked, dislike: wasLiked ? wasDisliked : false)
        likeCount += wasLiked ? -1 : 1

        do {
            try await BiliAPI.likeVideo(aid: detail.aid, like: !wasLiked)
        } catch {
            apply(like: wasLiked, dislike: wasDisliked)
            likeCount += wasLiked ? 1 : -1
            actionMessage = error.localizedDescription
        }
    }

    func toggleDislike(isLoggedIn: Bool) async {
        guard let detail, checkReady(.dislike, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.dislike) }

        let wasDisliked = relation?.isDisliked ?? false
        let wasLiked = relation?.isLiked ?? false
        apply(like: wasDisliked ? wasLiked : false, dislike: !wasDisliked)
        // 点踩会顺带取消点赞，点赞数要跟着减。
        if !wasDisliked, wasLiked { likeCount -= 1 }

        do {
            try await BiliAPI.dislikeVideo(aid: detail.aid, dislike: !wasDisliked)
        } catch {
            apply(like: wasLiked, dislike: wasDisliked)
            if !wasDisliked, wasLiked { likeCount += 1 }
            actionMessage = error.localizedDescription
        }
    }

    /// 一键投 1 币。已经投过的稿件不能再投，直接提示。
    func addCoin(isLoggedIn: Bool) async {
        guard let detail, checkReady(.coin, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.coin) }

        guard !(relation?.isCoined ?? false) else {
            actionMessage = "已经投过币了"
            return
        }

        let previousCoin = relation?.coin ?? 0
        apply(coin: 1)
        coinCount += 1

        do {
            try await BiliAPI.addCoin(aid: detail.aid, multiply: 1)
        } catch {
            // 只还原投币这一项。整个 relation 覆盖回去的话，会把这期间
            // 其它按钮刚改好的状态一起抹掉。
            apply(coin: previousCoin)
            coinCount -= 1
            actionMessage = error.localizedDescription
        }
    }

    /// 一键三连：点赞 + 投币 + 收藏到默认收藏夹。长按点赞按钮触发。
    ///
    /// 服务端一次做完三步，但三步是分别判定的（比如硬币不够只会让投币那一步
    /// 失败），所以这里按返回的字段逐项更新，而不是笼统当成全成功。
    func tripleAction(isLoggedIn: Bool) async {
        guard let detail, checkReady(.triple, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.triple) }

        guard !hasTripled else {
            actionMessage = "已经三连过了"
            return
        }

        do {
            let result = try await BiliAPI.tripleAction(aid: detail.aid)

            // 本来就已点赞/已收藏的，计数不能再加一次。
            if result.didLike, !(relation?.isLiked ?? false) { likeCount += 1 }
            if result.didFavorite, !(relation?.isFavorited ?? false) { favoriteCount += 1 }

            // 硬币要在原有基础上累加，不能直接用这次返回的 multiply 覆盖。
            // 已经投过币的稿件再三连时，投币那一步会被服务端跳过（multiply 为 0），
            // 照搬过来就把 coin 写成 0，投币按钮的高亮凭空消失了。
            let addedCoins = result.didCoin ? max(result.multiply ?? 1, 1) : 0
            coinCount += addedCoins
            let totalCoins = (relation?.coin ?? 0) + addedCoins

            apply(
                like: result.didLike ? true : nil,
                favorite: result.didFavorite ? true : nil,
                coin: totalCoins > 0 ? totalCoins : nil
            )
            actionMessage = tripleSummary(result)
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func tripleSummary(_ result: TripleResult) -> String {
        let failed = [
            result.didLike ? nil : "点赞",
            result.didCoin ? nil : "投币",
            result.didFavorite ? nil : "收藏"
        ].compactMap { $0 }
        return failed.isEmpty ? "三连成功" : "\(failed.joined(separator: "、"))没成功"
    }

    /// 已收藏状态下再点收藏按钮：从所有收藏夹里移除。
    /// 未收藏时不走这里，而是先弹收藏夹选择弹窗。
    func unfavoriteEverywhere(isLoggedIn: Bool) async {
        guard let detail, checkReady(.favorite, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.favorite) }

        let wasFavorited = relation?.isFavorited ?? false
        apply(favorite: false)
        favoriteCount = max(0, favoriteCount - 1)

        do {
            try await BiliAPI.unfavoriteEverywhere(aid: detail.aid)
            actionMessage = "已取消收藏"
        } catch {
            apply(favorite: wasFavorited)
            favoriteCount += 1
            actionMessage = error.localizedDescription
        }
    }

    /// 收藏夹弹窗确认后调用。两个列表分别是要加入和要移出的收藏夹。
    func updateFavorites(add: [Int], remove: [Int], isLoggedIn: Bool) async {
        guard let detail, checkReady(.favorite, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.favorite) }

        guard !add.isEmpty || !remove.isEmpty else { return }

        let wasFavorited = relation?.isFavorited ?? false
        let previousCount = favoriteCount
        let willBeFavorited = !add.isEmpty
        apply(favorite: willBeFavorited)
        // 收藏进多个收藏夹在计数上仍然只算一次收藏。
        if willBeFavorited, !wasFavorited {
            favoriteCount += 1
        } else if !willBeFavorited, wasFavorited {
            favoriteCount -= 1
        }

        do {
            try await BiliAPI.updateFavorites(
                aid: detail.aid,
                addFolderIDs: add,
                removeFolderIDs: remove
            )
            actionMessage = willBeFavorited ? "已收藏" : "已取消收藏"
        } catch {
            apply(favorite: wasFavorited)
            favoriteCount = previousCount
            actionMessage = error.localizedDescription
        }
    }

    func toggleFollow(isLoggedIn: Bool) async {
        guard let detail, checkReady(.follow, isLoggedIn: isLoggedIn) else { return }
        defer { busyActions.remove(.follow) }

        let wasFollowing = relation?.isFollowing ?? false
        apply(attention: !wasFollowing)

        do {
            try await BiliAPI.modifyRelation(mid: detail.owner.mid, follow: !wasFollowing)
        } catch {
            apply(attention: wasFollowing)
            actionMessage = error.localizedDescription
        }
    }

    // MARK: - 内部

    /// 未登录、详情还没到、或者上一次请求还没回来时都不该继续。
    private func checkReady(_ action: Action, isLoggedIn: Bool) -> Bool {
        guard isLoggedIn else {
            actionMessage = "请先登录"
            return false
        }
        guard !busyActions.contains(action) else { return false }
        busyActions.insert(action)
        return true
    }

    /// 只改 relation 中指定的几项，其余保持原值。
    private func apply(
        like: Bool? = nil,
        dislike: Bool? = nil,
        favorite: Bool? = nil,
        coin: Int? = nil,
        attention: Bool? = nil
    ) {
        let current = relation
        relation = VideoRelation(
            attention: attention ?? current?.attention,
            favorite: favorite ?? current?.favorite,
            like: like ?? current?.like,
            dislike: dislike ?? current?.dislike,
            coin: coin ?? current?.coin
        )
    }
}
