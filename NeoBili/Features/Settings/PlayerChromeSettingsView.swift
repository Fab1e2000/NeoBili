import SwiftUI
import UIKit

/// 播放器控件位置：按本机屏幕复刻全屏（横屏）或非全屏（视频页顶部）的播放区域，
/// 里面是真实的播放器控件，拖动滑条实时预览。两种状态各自一组设置。
struct PlayerChromeSettingsView: View {
    @State private var mode = PlayerChromeSettings.Mode.fullScreen
    private let screen = DeviceScreen.current

    var body: some View {
        Form {
            Section {
                Picker("状态", selection: $mode) {
                    ForEach(PlayerChromeSettings.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                Group {
                    switch mode {
                    case .fullScreen: FullScreenChromePreview(screen: screen)
                    case .inline: InlineChromePreview(screen: screen)
                    }
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } footer: {
                Text(mode == .fullScreen
                     ? "按本机屏幕的横屏尺寸等比缩小，圆角和灵动岛为近似示意。"
                     : "视频页顶部的播放区域，按本机屏幕宽度等比缩小。竖屏视频全屏播放时也使用这组设置。")
            }

            // 两组设置各用一套 @AppStorage，切换时整组换掉。
            PlayerChromeSliders(mode: mode, automaticSideInset: screen.landscapeSideInset)
                .id(mode)
        }
        .settingsPage("播放器控件位置")
    }
}

/// 一种状态的滑条和恢复默认。
private struct PlayerChromeSliders: View {
    let mode: PlayerChromeSettings.Mode
    /// 全屏「跟随系统」时滑条显示的数值。
    let automaticSideInset: CGFloat

    @AppStorage private var horizontalInset: Double
    @AppStorage private var topInset: Double
    @AppStorage private var bottomInset: Double
    @AppStorage private var spacing: Double

    private var defaults: PlayerChromeSettings.Values { PlayerChromeSettings.defaults(for: mode) }

    init(mode: PlayerChromeSettings.Mode, automaticSideInset: CGFloat) {
        self.mode = mode
        self.automaticSideInset = automaticSideInset
        let keys = PlayerChromeSettings.keys(for: mode)
        let defaults = PlayerChromeSettings.defaults(for: mode)
        _horizontalInset = AppStorage(wrappedValue: defaults.horizontalInset, keys.horizontalInset)
        _topInset = AppStorage(wrappedValue: defaults.topInset, keys.topInset)
        _bottomInset = AppStorage(wrappedValue: defaults.bottomInset, keys.bottomInset)
        _spacing = AppStorage(wrappedValue: defaults.spacing, keys.spacing)
    }

    private var isAutomaticSide: Bool { mode == .fullScreen && horizontalInset < 0 }

    var body: some View {
        Section {
            slider("左右边距",
                   value: Binding(get: { isAutomaticSide ? Double(automaticSideInset) : horizontalInset },
                                  set: { horizontalInset = $0 }),
                   range: PlayerChromeSettings.horizontalInsetRange(for: mode),
                   note: isAutomaticSide ? "跟随系统" : nil)
            slider("上边距", value: $topInset, range: PlayerChromeSettings.verticalInsetRange)
            slider("下边距", value: $bottomInset, range: PlayerChromeSettings.verticalInsetRange)
            slider("控件间距", value: $spacing, range: PlayerChromeSettings.spacingRange)
        } footer: {
            if mode == .fullScreen {
                Text("左右边距默认跟随系统横屏安全区，正好避开屏幕圆角和灵动岛；调得太小时控件会伸进四角的圆弧里。")
            }
        }

        Section {
            Button("恢复默认") {
                horizontalInset = defaults.horizontalInset
                topInset = defaults.topInset
                bottomInset = defaults.bottomInset
                spacing = defaults.spacing
            }
            .disabled(horizontalInset == defaults.horizontalInset && topInset == defaults.topInset
                      && bottomInset == defaults.bottomInset && spacing == defaults.spacing)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(title) {
                Text(note.map { "\(Int(value.wrappedValue.rounded())) pt · \($0)" } ?? "\(Int(value.wrappedValue.rounded())) pt")
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value.wrappedValue.rounded())) 点")
        }
    }
}

/// 本机屏幕尺寸与避让参数，用当前（竖屏）窗口推算。
struct DeviceScreen {
    /// 竖屏时的屏幕尺寸（宽 < 高）。
    let portraitSize: CGSize
    /// 竖屏时的顶部安全区（状态栏 / 灵动岛）。
    let portraitTopInset: CGFloat
    /// 横屏时左右的系统安全区：刘海/灵动岛机型等于竖屏时的顶部安全区。
    let landscapeSideInset: CGFloat
    /// 屏幕圆角的近似值（与顶部安全区相近），只用于预览画框。
    let cornerRadius: CGFloat
    let hasDynamicIsland: Bool

    var landscapeSize: CGSize { CGSize(width: portraitSize.height, height: portraitSize.width) }

    @MainActor static var current: DeviceScreen {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bounds = scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 402, height: 874)
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        // 设置页是竖屏：横屏时左右的安全区等于此时的顶部安全区（已经在横屏时则直接取左侧）。
        let sideInset = max(window?.safeAreaInsets.top ?? 62, window?.safeAreaInsets.left ?? 0)
        return DeviceScreen(
            portraitSize: CGSize(width: min(bounds.width, bounds.height), height: max(bounds.width, bounds.height)),
            portraitTopInset: sideInset,
            landscapeSideInset: sideInset,
            cornerRadius: min(max(sideInset, 20), 64),
            hasDynamicIsland: sideInset >= 59
        )
    }
}

/// 预览里用的示例控件：真实的 `PlayerGlassChrome`，读同一组设置，滑条一动就重排。
private struct SampleChrome: View {
    let isFullScreen: Bool
    let safeAreaInsets: EdgeInsets

    var body: some View {
        PlayerGlassChrome(
            title: "示例视频标题",
            videoQualityControl: PlayerQualityControl(title: "1080P", accessibilityLabel: "分辨率", options: [],
                                                     selectedID: 0, isEnabled: true, onSelect: { _ in }),
            audioQualityControl: PlayerQualityControl(title: "192K", accessibilityLabel: "音质", options: [],
                                                     selectedID: 0, isEnabled: true, onSelect: { _ in }),
            position: 83, duration: 300, buffered: 120,
            isPlaying: true, canControlPlayback: true, isFullScreen: isFullScreen,
            safeAreaInsets: safeAreaInsets,
            isDanmakuEnabled: true, showsDanmakuToggle: true, onToggleDanmaku: {},
            onSendDanmaku: isFullScreen ? {} : nil
        ) { EmptyView() }
    }
}

private let sampleVideo = LinearGradient(
    colors: [Color(red: 0.35, green: 0.3, blue: 0.75), Color(red: 0.1, green: 0.45, blue: 0.6)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

/// 把按实际点数排版的内容等比缩小到预览宽度。
private struct ScaledScreen<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(geometry.size.width / size.width, anchor: .topLeading)
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放器控件位置预览")
    }
}

/// 横屏全屏：居中的 16:9 画面、两侧黑边、四角圆角和一侧的灵动岛。
private struct FullScreenChromePreview: View {
    let screen: DeviceScreen

    var body: some View {
        let size = screen.landscapeSize
        ScaledScreen(size: size) {
            ZStack {
                Color.black
                sampleVideo.frame(width: size.height * 16 / 9, height: size.height)
                SampleChrome(isFullScreen: true,
                             safeAreaInsets: EdgeInsets(top: 0, leading: screen.landscapeSideInset,
                                                        bottom: 21, trailing: screen.landscapeSideInset))
                if screen.hasDynamicIsland {
                    // 横屏时灵动岛在一侧的中间；画在黑边上看不见，加一圈淡描边示意位置。
                    Capsule()
                        .fill(.black)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1.5) }
                        .frame(width: 37, height: 126)
                        .position(x: 11 + 37 / 2, y: size.height / 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: screen.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: screen.cornerRadius, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 2)
            }
        }
    }
}

/// 非全屏：竖屏手机的顶部——状态栏、灵动岛和下面 16:9 的播放区域。
private struct InlineChromePreview: View {
    let screen: DeviceScreen

    var body: some View {
        let width = screen.portraitSize.width
        let videoHeight = width * 9 / 16
        let size = CGSize(width: width, height: screen.portraitTopInset + videoHeight)
        ScaledScreen(size: size) {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    if screen.hasDynamicIsland {
                        Capsule()
                            .fill(.black)
                            .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1.5) }
                            .frame(width: 126, height: 37)
                    }
                }
                .frame(height: screen.portraitTopInset)
                ZStack {
                    sampleVideo
                    SampleChrome(isFullScreen: false, safeAreaInsets: EdgeInsets())
                }
                .frame(height: videoHeight)
            }
            // 只截取手机顶部：上面两个角是屏幕圆角，下沿直接截断。
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: screen.cornerRadius,
                                              topTrailingRadius: screen.cornerRadius, style: .continuous))
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: screen.cornerRadius,
                                       topTrailingRadius: screen.cornerRadius, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 2)
            }
        }
    }
}
