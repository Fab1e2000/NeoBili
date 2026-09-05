import SwiftUI
import UIKit

/// 首页刷新动画的全部可调参数。
///
/// 三段式：松手后旧卡片原地缓慢淡出；数据没回来就停在很淡的残留上（可以无限久）；
/// 数据到达后残留淡尽，新卡从镜头前上方落下。
///
/// 退出动画作用在真实的卡片视图上，只改一个 opacity——不位移、不缩放、不截图。
/// 之前用滚动视图的位图做残影，位图和真实视图的位置总对不齐，就是"闪到下方"的来源。
/// 这些数字是拍脑袋的初值，真机上边看边改就行，改完不用动别的地方。
/// 界面动画的快慢。倍率越大越快，实际时长是基准时长除以倍率。
/// 设置页给两条滑杆：退出（旧内容离场）和进入（新内容登场）。
///
/// 目前管两处：首页下拉刷新的淡出/落位，以及三个主页面之间的切换。
/// 键名里的 feed 是历史遗留，改了会丢掉用户已经存下的档位，所以留着。
enum AnimationSpeedSettings {
    static let exitSpeedKey = "neobili.feedExitSpeed"
    static let enterSpeedKey = "neobili.feedEnterSpeed"
    static let defaultSpeed = 1.0
    static let range = 0.1...10.0

    /// 主页面切换时单侧淡出/淡入的基准时长。
    ///
    /// 比刷新的淡出短得多：Tab 的高亮要等内容切完才会移动（TabView 的高亮和
    /// 内容共用同一个 selection），淡出太长就会显得"点了没反应"。
    static let tabFadeDuration: Double = 0.25

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultSpeed
    }

    static func tabFade(speed: Double) -> Double {
        tabFadeDuration / clamped(speed)
    }
}

enum FeedRefreshTuning {
    // MARK: 淡出（旧内容退出）

    /// 旧卡片淡尽所需的时间，与网络无关：松手就开始，跑完就是跑完。
    ///
    /// 早先的版本会在中途停在一个很淡的浓度上等数据，好处是慢网络下画面不全空，
    /// 代价是那个停顿看起来像卡死——尤其把速度调快之后，停顿来得更早也更明显。
    /// 现在不再等：淡出自己走完，数据没到就是空屏，到了再让新卡片落位。
    static let fadeExitDuration: Double = 0.9

    static func fadeExit(speed: Double) -> Double {
        fadeExitDuration / AnimationSpeedSettings.clamped(speed)
    }

    // MARK: 落位（新内容）

    /// 新卡起始位置在屏幕上方多远。
    static let dropRise: CGFloat = 170
    /// 起始比最终大，等于离镜头更近。
    static let dropScale: CGFloat = 1.24
    /// 绕 X 轴前倾，配合 perspective 做出"朝着用户的上方"。
    static let dropTilt: Double = -16
    static let dropPerspective: CGFloat = 0.55
    /// 相邻两行的落位间隔（倍率为 1 时）。
    static let staggerDuration: Double = 0.055
    /// 只有首屏这几行做落位动画。再往下的行是懒加载出来的，
    /// 给它们加动画会变成"滚到哪掉到哪"。
    static let staggerRows = 4
    /// 单行落位的基准时长。
    static let landingDuration: Double = 0.55
    static let landingBounce: Double = 0.08

    static func stagger(speed: Double) -> Double { staggerDuration / AnimationSpeedSettings.clamped(speed) }

    static func landing(speed: Double) -> Animation {
        .snappy(duration: landingDuration / AnimationSpeedSettings.clamped(speed), extraBounce: landingBounce)
    }

    /// 落位窗口：这段时间内新建出来的行才播落位动画。
    /// 关掉之后再新建的行（比如用户滚下去又滚回来）保持原样，
    /// 否则就成了"滚到哪掉到哪"。
    static func landingWindow(speed: Double) -> Double {
        (landingDuration + staggerDuration * Double(staggerRows)) / AnimationSpeedSettings.clamped(speed)
    }

    // MARK: 下拉过程

    /// 下拉到阈值时列表淡掉的幅度，是退出动画的预告，也代替原来那颗提示胶囊。
    /// 松手后就从这个浓度接着往下淡，中间没有跳变。
    static let pullFade: Double = 0.18
}

/// 新卡的落位变换。`progress` 0 = 起始（镜头前上方），1 = 落到位。
struct FeedDropInEffect: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        let remaining = 1 - progress
        content
            .scaleEffect(1 + (FeedRefreshTuning.dropScale - 1) * remaining)
            .rotation3DEffect(
                .degrees(FeedRefreshTuning.dropTilt * remaining),
                axis: (x: 1, y: 0, z: 0),
                perspective: FeedRefreshTuning.dropPerspective
            )
            .offset(y: -FeedRefreshTuning.dropRise * remaining)
            .opacity(progress)
    }
}

/// 包住首页的一行卡片，负责刷新完成后的落位动画。
///
/// 刷新会把新视频插到列表最前面，行的 id 跟着变，所以首屏这几行在刷新后是
/// **全新的视图**而不是沿用下来的——落位动画因此必须在创建时就能自己跑起来，
/// 光靠 `onChange(of: generation)` 是等不到的。行一出生就是全透明的起始态，
/// 不会先闪一下已经落位的样子。
struct FeedDropInRow<Content: View>: View {
    let index: Int
    let generation: Int
    /// 落位窗口是否开着。只有开着时新建的行才播动画。
    let landing: Bool
    /// 落位速度倍率，来自设置页。
    let speed: Double
    let reduceMotion: Bool
    @ViewBuilder var content: Content

    @State private var progress: Double
    /// 已经为哪一代播过动画，避免同一代播两次。
    @State private var playedGeneration: Int?

    init(
        index: Int,
        generation: Int,
        landing: Bool,
        speed: Double,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.index = index
        self.generation = generation
        self.landing = landing
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.content = content()
        let willAnimate = landing && !reduceMotion && index < FeedRefreshTuning.staggerRows
        _progress = State(initialValue: willAnimate ? 0 : 1)
    }

    private var animates: Bool {
        landing && !reduceMotion && index < FeedRefreshTuning.staggerRows
    }

    var body: some View {
        content
            .modifier(FeedDropInEffect(progress: progress))
            // 刷新后新建出来的行走这条。
            .task { play() }
            // id 没变、被沿用下来的行走这条（比如刷新没拿到新内容）。
            .onChange(of: generation) { play() }
    }

    private func play() {
        guard animates, playedGeneration != generation else { return }
        playedGeneration = generation
        // 沿用下来的行此刻还停在落位状态，先无动画地放回起点。
        // 新建的行本来就是 0，这一句是空操作。
        progress = 0
        Task { @MainActor in
            // 隔一帧再启动：同一帧内改两次状态会被合并成"没有动画"。
            try? await Task.sleep(for: .milliseconds(16))
            let delay = Double(index) * FeedRefreshTuning.stagger(speed: speed)
            withAnimation(FeedRefreshTuning.landing(speed: speed).delay(delay)) {
                progress = 1
            }
        }
    }
}
