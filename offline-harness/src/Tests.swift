import Foundation

// MARK: - 测试基础设施

@MainActor
final class LoaderRecorder {
    /// loader 被真正调用的次数（按 bvid 记录）。
    private(set) var calls: [String] = []
    private(set) var maxInFlight = 0
    private var inFlight = 0
    /// 前 holdCount 次调用挂起，等待测试放行；之后的调用直接通过。
    private var holdBudget: Int
    private var held: [CheckedContinuation<Void, Never>] = []
    private let result: @MainActor (String) -> PortraitVideoStore.Metadata
    private let shouldFail: (String) -> Bool

    init(
        holdCount: Int = 0,
        result: @escaping @MainActor (String) -> PortraitVideoStore.Metadata = { _ in
            PortraitVideoStore.Metadata(dimension: VideoDimension(width: 1920, height: 1080), durationSeconds: 100)
        },
        shouldFail: @escaping (String) -> Bool = { _ in false }
    ) {
        self.holdBudget = holdCount
        self.result = result
        self.shouldFail = shouldFail
    }

    private func enter(_ bvid: String) async {
        calls.append(bvid)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        if holdBudget > 0 {
            holdBudget -= 1
            await withCheckedContinuation { held.append($0) }
        }
        inFlight -= 1
    }

    func releaseHeld() {
        let pending = held
        held.removeAll()
        pending.forEach { $0.resume() }
    }

    var loader: @MainActor (String) async throws -> PortraitVideoStore.Metadata {
        { [self] bvid in
            try Task.checkCancellation()
            await enter(bvid)
            if shouldFail(bvid) { throw BiliAPIError.httpStatus(-1) }
            return result(bvid)
        }
    }
}

@MainActor
func waitUntil(
    _ message: String,
    timeout: TimeInterval = 5,
    _ condition: () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            fatalError("等待超时：\(message)")
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

struct TestItem: VideoDimensionProviding {
    let bvid: String
    let dimension: VideoDimension?
    let duration: Int?

    var dimensionLookupBVID: String? { bvid }
    var videoDurationSeconds: Int? { duration }
}

@MainActor
@main
struct Harness {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS  \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    static func main() async throws {
        // 看门狗：任何挂死都让进程以失败退出，而不是无限等。
        Task.detached {
            try? await Task.sleep(for: .seconds(60))
            print("FAIL  全局看门狗超时，测试挂死")
            exit(2)
        }

        await testDurationParsing()
        await testVideoDimension()
        await testFilterSemantics()
        await testStoreDedupAndCooldown()
        await testStoreConcurrencyCap()
        await testStoreCancellation()
        await testFeedRowGrouping()
        await testEnvironmentAction()
        await testWBICacheFreshness()
        await testLenientDynamicDecoding()

        if failures == 0 {
            print("ALL PASS")
        } else {
            print("FAILURES: \(failures)")
            exit(1)
        }
        exit(0)
    }

    // MARK: 时长解析

    static func testDurationParsing() {
        expect(VideoDurationFilterSettings.seconds(from: "12:34") == 754, "时长 M:SS")
        expect(VideoDurationFilterSettings.seconds(from: "1:02:03") == 3723, "时长 H:MM:SS")
        expect(VideoDurationFilterSettings.seconds(from: "1:2") == 62, "时长 M:S 单数位")
        expect(VideoDurationFilterSettings.seconds(from: " 12:34 ") == 754, "时长两侧空白")
        expect(VideoDurationFilterSettings.seconds(from: "90") == 90, "时长裸秒数")
        expect(VideoDurationFilterSettings.seconds(from: "0:00") == nil, "时长全零交给详情补查")
        expect(VideoDurationFilterSettings.seconds(from: "12:60") == nil, "秒位越界视为无法解析")
        expect(VideoDurationFilterSettings.seconds(from: "-1:00") == nil, "负数拒绝")
        expect(VideoDurationFilterSettings.seconds(from: "") == nil, "空串拒绝")
        expect(VideoDurationFilterSettings.seconds(from: "1:2:3:4") == nil, "四段拒绝")
    }

    // MARK: 画幅判断

    static func testVideoDimension() {
        let portrait = VideoDimension(width: 1080, height: 1920)
        expect(portrait.isValid && portrait.isPortrait, "1080x1920 是竖屏")

        let rotated = VideoDimension(width: 1920, height: 1080, rotate: 90)
        expect(rotated.isPortrait, "1920x1080 + rotate 90 交换后是竖屏")

        let rotatedBack = VideoDimension(width: 1080, height: 1920, rotate: 270)
        expect(!rotatedBack.isPortrait, "1080x1920 + rotate 270 交换后是横屏")

        let weird = VideoDimension(width: 1920, height: 1080, rotate: 450)
        expect(weird.isPortrait, "rotate 450 归一化为 90")

        let square = VideoDimension(width: 500, height: 500)
        expect(square.isValid && !square.isPortrait, "正方形按横屏保留（严格大于才算竖屏）")

        let invalid = VideoDimension(width: 0, height: 1080)
        expect(!invalid.isValid && !invalid.isPortrait, "零宽无效，也不算竖屏")

        let data = Data(#"{"width":"1920","height":"1080","rotate":0}"#.utf8)
        let decoded = try? JSONDecoder().decode(VideoDimension.self, from: data)
        expect(decoded?.width == 1920 && decoded?.height == 1080, "字符串宽高可解码")
    }

    // MARK: 过滤语义（竖屏 + 最低时长，走真实扩展方法）

    static func testFilterSemantics() async {
        // 真实的 canDisplayVideo(hidingPortrait:) 从共享设置读最低时长；
        // 结束后恢复原值。
        let originalMinutes = VideoDurationFilterSettings.shared.minimumMinutes
        VideoDurationFilterSettings.shared.minimumMinutes = 10 // 600 秒
        defer { VideoDurationFilterSettings.shared.minimumMinutes = originalMinutes }

        // 时长阈值边界：恰好达到保留（>=）。
        let atThreshold = TestItem(bvid: "at", dimension: VideoDimension(width: 1920, height: 1080), duration: 600)
        expect(atThreshold.canDisplayVideo(hidingPortrait: false), "恰好 600 秒、阈值 600 秒：保留")
        expect(atThreshold.metadataRequest(hidingPortrait: false, minimumSeconds: 600) == nil,
               "画幅时长都已知且达标：不需要补查")

        let below = TestItem(bvid: "below", dimension: VideoDimension(width: 1920, height: 1080), duration: 599)
        expect(!below.canDisplayVideo(hidingPortrait: false), "599 秒、阈值 600 秒：隐藏")

        // 画幅已知竖屏：不补查、隐藏。
        let knownPortrait = TestItem(bvid: "p", dimension: VideoDimension(width: 1080, height: 1920), duration: 700)
        expect(knownPortrait.metadataRequest(hidingPortrait: true, minimumSeconds: 0) == nil,
               "画幅已知竖屏：不再补查")
        expect(!knownPortrait.canDisplayVideo(hidingPortrait: true), "已知竖屏：隐藏")

        // 未开启任何过滤：不补查、全保留。
        let known = TestItem(bvid: "x", dimension: nil, duration: 700)
        expect(known.metadataRequest(hidingPortrait: false, minimumSeconds: 0) == nil, "过滤全关：不补查")
        expect(known.canDisplayVideo(hidingPortrait: false), "过滤全关：保留")

        // 只开时长过滤、时长未知：补查且带时长要求；补查前隐藏。
        let durationUnknown = TestItem(bvid: "d", dimension: VideoDimension(width: 1920, height: 1080), duration: nil)
        let request = durationUnknown.metadataRequest(hidingPortrait: false, minimumSeconds: 60)
        expect(request?.requiringDuration == true, "时长未知：补查详情（含时长要求）")
        expect(!durationUnknown.canDisplayVideo(hidingPortrait: false), "时长未知：补查前隐藏")

        // 两个过滤同时开：竖屏或过短任一成立都隐藏。
        let shortLandscape = TestItem(bvid: "sl", dimension: VideoDimension(width: 1920, height: 1080), duration: 30)
        expect(!shortLandscape.canDisplayVideo(hidingPortrait: false), "横屏但过短：隐藏")
        let longPortrait = TestItem(bvid: "lp", dimension: VideoDimension(width: 1080, height: 1920), duration: 700)
        expect(!longPortrait.canDisplayVideo(hidingPortrait: true), "竖屏但够长：仍隐藏")

        // 详情缓存补齐列表缺失的信息：画幅、时长都未知时，shared store
        // 的补查（stub 返回横屏 + 700 秒）让它从「隐藏」变为「保留」。
        // 探针 ID 每次运行唯一：进程的 UserDefaults 是持久化的，
        // 固定 ID 会被上一轮的结果提前「补齐」。
        let probeID = "shared-probe-\(UUID().uuidString)"
        let probe = TestItem(bvid: probeID, dimension: nil, duration: nil)
        expect(!probe.canDisplayVideo(hidingPortrait: false), "列表与缓存都未知：隐藏")
        expect(probe.metadataRequest(hidingPortrait: false, minimumSeconds: 600)?.bvid == probeID,
               "未知条目进入补查清单")
        await PortraitVideoStore.shared.resolve([probeID])
        expect(probe.canDisplayVideo(hidingPortrait: false), "详情补查后（700 秒横屏）：保留")
        expect(PortraitVideoStore.shared.hasFreshAttempt(bvid: probeID, requiringDuration: true),
               "补查结果带时长标记，满足 requiringDuration 的复用")
    }

    // MARK: PortraitVideoStore 去重与冷却

    static func testStoreDedupAndCooldown() async {
        let defaults = UserDefaults(suiteName: "harness.dedup")!
        defaults.removePersistentDomain(forName: "harness.dedup")
        var current = Date(timeIntervalSince1970: 1_000_000)

        let recorder = LoaderRecorder()
        let store = PortraitVideoStore(defaults: defaults, now: { current }, metadataLoader: recorder.loader)

        // 同一 bvid 的并发请求只发一次。
        async let a: Void = store.resolve(["shared"])
        async let b: Void = store.resolve(["shared"])
        await a
        await b
        expect(recorder.calls.count == 1, "同一 bvid 并发补查只发一次请求（实际 \(recorder.calls.count) 次）")

        // 详情里画幅和时长都拿到了：一周内不再补查。
        expect(store.isPortrait(bvid: "shared") == false, "补查结果：横屏")
        expect(store.durationSeconds(bvid: "shared") == 100, "补查结果：时长 100 秒")
        current.addTimeInterval(6 * 86_400)
        await store.resolve(["shared"])
        expect(recorder.calls.count == 1, "六天后仍在有效期内：不补查")

        // 过期后重新补查。
        current.addTimeInterval(2 * 86_400)
        await store.resolve(["shared"])
        expect(recorder.calls.count == 2, "超过七天有效期后重新补查")

        // 失败五分钟冷却。
        let failRecorder = LoaderRecorder(shouldFail: { _ in true })
        let failStore = PortraitVideoStore(defaults: defaults, now: { current }, metadataLoader: failRecorder.loader)
        await failStore.resolve(["broken"])
        await failStore.resolve(["broken"])
        expect(failRecorder.calls.count == 1, "失败后进入冷却，不立即重试（实际 \(failRecorder.calls.count) 次）")
        expect(failStore.isPortrait(bvid: "broken") == nil, "失败不当作横屏")
        current.addTimeInterval(400)
        await failStore.resolve(["broken"])
        expect(failRecorder.calls.count == 2, "冷却结束后允许重试")

        // 持久化：新实例（同一 defaults、时间推进在有效期内）直接读盘，不发请求。
        let persistedRecorder = LoaderRecorder()
        let persisted = PortraitVideoStore(defaults: defaults, now: { current }, metadataLoader: persistedRecorder.loader)
        await persisted.resolve(["shared"])
        expect(persistedRecorder.calls.isEmpty, "重启后读已持久化的补查结果，不重复请求")
    }

    // MARK: 补查并发上限

    static func testStoreConcurrencyCap() async {
        let defaults = UserDefaults(suiteName: "harness.cap")!
        defaults.removePersistentDomain(forName: "harness.cap")

        let total = 200
        // 前 50 次调用挂住，观察并发上限；其余放行。
        let recorder = LoaderRecorder(holdCount: 50)
        let store = PortraitVideoStore(defaults: defaults, metadataLoader: recorder.loader)

        let task = Task {
            await store.resolve((0..<total).map { "bv-\($0)" })
        }
        try? await waitUntil("前 50 个补查挂起") { recorder.calls.count == 50 }
        expect(recorder.maxInFlight <= 50, "同时补查不超过 50（实测 \(recorder.maxInFlight)）")
        expect(recorder.calls.count == 50, "挂住期间不再发起新请求")

        recorder.releaseHeld()
        await task.value
        expect(recorder.calls.count == total, "放行后全部补查完成（实际 \(recorder.calls.count)）")
        expect(recorder.maxInFlight <= 50, "整个过程并发都不超过 50（实测 \(recorder.maxInFlight)）")
    }

    static func testStoreCancellation() async {
        let suite = "harness.cancel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = LoaderRecorder(holdCount: 50)
        let store = PortraitVideoStore(defaults: defaults, metadataLoader: recorder.loader)
        let active = Task { await store.resolve((0..<50).map { "active-\($0)" }) }
        try? await waitUntil("占满 50 个请求") { recorder.calls.count == 50 }

        var queuedFinished = false
        let queued = Task {
            await store.resolve((0..<50).map { "cancel-\($0)" })
            queuedFinished = true
        }
        try? await waitUntil("50 条请求排队") { store.queuedRequestCount == 50 }
        queued.cancel()
        try? await waitUntil("取消后立即退出，不等在途请求完成") { queuedFinished }
        expect(store.queuedRequestCount == 0, "取消后移除无人等待的排队请求")
        expect(recorder.calls.count == 50, "取消的排队请求没有发出网络调用")
        expect(!store.hasFreshAttempt(bvid: "cancel-0"), "取消排队不写失败缓存")

        let first = Task { await store.resolve(["shared-queued"]) }
        let second = Task { await store.resolve(["shared-queued"]) }
        try? await waitUntil("两个等待者共享排队请求") { store.subscriberCount(for: "shared-queued") == 2 }
        first.cancel()
        await first.value
        expect(store.subscriberCount(for: "shared-queued") == 1, "取消一个等待者不会取消另一个等待者")
        expect(store.queuedRequestCount == 1, "仍有人等待的请求继续排队")

        recorder.releaseHeld()
        await active.value
        await second.value
        expect(recorder.calls.filter { $0 == "shared-queued" }.count == 1, "共享排队请求只发一次")
        expect(store.isPortrait(bvid: "shared-queued") == false, "剩余等待者获得有效结果")
        expect(!recorder.calls.contains { $0.hasPrefix("cancel-") }, "释放名额后取消批次仍不发请求")
        await store.resolve(["cancel-0"])
        expect(recorder.calls.filter { $0 == "cancel-0" }.count == 1, "取消后同一视频可重新申请")
        expect(recorder.maxInFlight <= 50, "取消与共享交错时并发仍不超过 50")

        let inFlightRecorder = LoaderRecorder(holdCount: 1)
        let inFlightStore = PortraitVideoStore(defaults: defaults, metadataLoader: inFlightRecorder.loader)
        let subscriber = Task { await inFlightStore.resolve(["in-flight"]) }
        try? await waitUntil("请求已开始") { inFlightRecorder.calls.count == 1 }
        subscriber.cancel()
        await subscriber.value
        expect(inFlightRecorder.calls.count == 1, "取消在途请求的等待者可立即退出")
        inFlightRecorder.releaseHeld()
        try? await waitUntil("在途请求仍完成并缓存") { inFlightStore.isPortrait(bvid: "in-flight") == false }
        await inFlightStore.resolve(["in-flight"])
        expect(inFlightRecorder.calls.count == 1, "已完成的共享请求可继续复用缓存")
    }

    // MARK: 首页行分组

    static func testFeedRowGrouping() {
        func video(_ id: String) -> HomeFeedItem { .video(VideoSummary(
            bvid: id, aid: 1, cid: 1, title: id, pic: "", desc: "", duration: 1, pubdate: 1,
            owner: VideoOwner(mid: 1, name: "", face: ""),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)
        )) }

        let mixed = HomeFeedRow.group([video("a"), video("b"), .lastSeen, video("c")])
        expect(mixed.count == 3, "提示卡把行隔开")
        if case .videos(let pair) = mixed[0] { expect(pair.map(\.bvid) == ["a", "b"], "提示卡前成对") }
        if case .lastSeen = mixed[1] { expect(true, "第二行是提示卡") }
        if case .videos(let tail) = mixed[2] { expect(tail.map(\.bvid) == ["c"], "提示卡后接尾行") }

        let leadingMarker = HomeFeedRow.group([.lastSeen, video("a")])
        if case .lastSeen = leadingMarker[0] { expect(true, "行首提示卡独立成行") }

        let oddTail = HomeFeedRow.group([video("a"), video("b"), video("c")])
        expect(oddTail.count == 2, "奇数尾部单独成行")
    }

    // MARK: EnvironmentAction

    static func testEnvironmentAction() {
        let box = EnvironmentAction<Int> { _ in }
        let same = box
        expect(box == same, "同一实例相等")
        expect(box != EnvironmentAction<Int> { _ in }, "不同实例不等")

        var received: Int?
        box.setHandler { received = $0 }
        box(7)
        expect(received == 7, "setHandler 后动作生效")
        expect(received != nil && box == same, "换 handler 不改变盒子身份")
    }

    // MARK: WBI 缓存按自然日有效

    static func testWBICacheFreshness() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 23))!
        let nextMorning = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 8))!
        expect(WBISigner.isCacheFresh(savedAt: noon, now: lateNight, calendar: calendar), "同一天有效")
        expect(!WBISigner.isCacheFresh(savedAt: noon, now: nextMorning, calendar: calendar), "跨自然日过期")
    }

    // MARK: 动态宽松解码

    static func testLenientDynamicDecoding() {
        let json = Data("""
        {"items": [
            {"id_str": "1", "type": "DYNAMIC_TYPE_AV",
             "modules": {"module_author": {"mid": 9, "name": "UP", "face": "", "pub_time": "3小时前", "pub_ts": 100},
                         "module_dynamic": {"major": {"archive": {"aid": "77", "bvid": "BV1", "title": "T",
                                             "cover": "", "duration_text": "1:00", "stat": {"play": "1.2万", "danmaku": "9"},
                                             "dimension": {"width": 1080, "height": 1920, "rotate": 0}}}},
                         "module_stat": {"comment": {"count": 2}, "forward": {"count": 3}, "like": {"count": 4, "status": 1}}},
             "basic": {"comment_id_str": 55, "comment_type": 1}},
            {"id_str": "2", "type": "DYNAMIC_TYPE_FORWARD"},
            null,
            {"id_str": "3", "type": "DYNAMIC_TYPE_WORD",
             "modules": {"module_dynamic": {"desc": {"text": "纯文字"}}}},
            {"id_str": "4", "type": "DYNAMIC_TYPE_DRAW",
             "modules": {"module_dynamic": {"major": {"draw": {"items": [{"src": "//i0.hdslb.com/a.jpg", "width": 100, "height": 200}]}}}}}
        ], "offset": 42, "has_more": 1}
        """.utf8)

        let page = try? JSONDecoder().decode(DynamicFeedPage.self, from: json)
        expect(page != nil, "动态整页可解码")
        expect(page?.offset == "42", "数字 offset 转字符串")
        expect(page?.hasMore == true, "数字 has_more 转布尔")
        expect(page?.entries.count == 3, "转发/坏条目被跳过，其余保留（实际 \(page?.entries.count ?? -1) 条）")
        let av = page?.entries.first
        expect(av?.video?.aid == 77, "字符串 aid 可解")
        expect(av?.video?.dimension?.isPortrait == true, "动态视频自带画幅（竖屏）")
        expect(av?.isLikedByServer == true, "数字点赞状态转布尔")
        expect(av?.commentOid == 55 && av?.commentType == 1, "评论区定位齐全")
        let draw = page?.entries.last
        expect(draw?.images.count == 1 && draw?.images[0].secureURL?.absoluteString.hasPrefix("https://") == true,
               "协议相对图片地址补 https")
    }
}
