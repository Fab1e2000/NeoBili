import SwiftUI
import UIKit

/// 全屏播放器控件位置：按本机屏幕复刻一个横屏窗口，里面是真实的全屏控件，拖动滑条实时预览。
struct FullScreenChromeSettingsView: View {
    @AppStorage(FullScreenChromeSettings.horizontalInsetKey) private var horizontalInset = FullScreenChromeSettings.automaticHorizontalInset
    @AppStorage(FullScreenChromeSettings.topInsetKey) private var topInset = FullScreenChromeSettings.defaultTopInset
    @AppStorage(FullScreenChromeSettings.bottomInsetKey) private var bottomInset = FullScreenChromeSettings.defaultBottomInset
    @AppStorage(FullScreenChromeSettings.spacingKey) private var spacing = FullScreenChromeSettings.defaultSpacing

    private let screen = DeviceScreen.current

    var body: some View {
        Form {
            Section {
                FullScreenChromePreview(screen: screen)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } footer: {
                Text("按本机屏幕的横屏尺寸等比缩小，圆角和灵动岛为近似示意。")
            }

            Section {
                slider("左右边距",
                       value: Binding(get: { horizontalInset < 0 ? Double(screen.landscapeSideInset) : horizontalInset },
                                      set: { horizontalInset = $0 }),
                       range: FullScreenChromeSettings.horizontalInsetRange,
                       note: horizontalInset < 0 ? "跟随系统" : nil)
                slider("上边距", value: $topInset, range: FullScreenChromeSettings.verticalInsetRange)
                slider("下边距", value: $bottomInset, range: FullScreenChromeSettings.verticalInsetRange)
                slider("控件间距", value: $spacing, range: FullScreenChromeSettings.spacingRange)
            } footer: {
                Text("左右边距默认跟随系统横屏安全区，正好避开屏幕圆角和灵动岛；调得太小时控件会伸进四角的圆弧里。")
            }

            Section {
                Button("恢复默认") {
                    horizontalInset = FullScreenChromeSettings.automaticHorizontalInset
                    topInset = FullScreenChromeSettings.defaultTopInset
                    bottomInset = FullScreenChromeSettings.defaultBottomInset
                    spacing = FullScreenChromeSettings.defaultSpacing
                }
                .disabled(horizontalInset < 0 && topInset == FullScreenChromeSettings.defaultTopInset
                          && bottomInset == FullScreenChromeSettings.defaultBottomInset
                          && spacing == FullScreenChromeSettings.defaultSpacing)
            }
        }
        .settingsPage("全屏控件位置")
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

/// 本机屏幕的横屏尺寸与避让参数，用竖屏时的窗口推算。
struct DeviceScreen {
    /// 横屏时的屏幕尺寸（宽 > 高）。
    let landscapeSize: CGSize
    /// 横屏时左右的系统安全区：刘海/灵动岛机型等于竖屏时的顶部安全区。
    let landscapeSideInset: CGFloat
    /// 屏幕圆角的近似值（与顶部安全区相近），只用于预览画框。
    let cornerRadius: CGFloat
    let hasDynamicIsland: Bool

    @MainActor static var current: DeviceScreen {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let bounds = scene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 402, height: 874)
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        // 设置页是竖屏：横屏时左右的安全区等于此时的顶部安全区（已经在横屏时则直接取左侧）。
        let sideInset = max(window?.safeAreaInsets.top ?? 62, window?.safeAreaInsets.left ?? 0)
        return DeviceScreen(
            landscapeSize: CGSize(width: max(bounds.width, bounds.height), height: min(bounds.width, bounds.height)),
            landscapeSideInset: sideInset,
            cornerRadius: min(max(sideInset, 20), 64),
            hasDynamicIsland: sideInset >= 59
        )
    }
}

/// 缩小后的横屏窗口：示意视频画面 + 真实的全屏控件（读同一组设置，拖动滑条即时更新）。
private struct FullScreenChromePreview: View {
    let screen: DeviceScreen

    var body: some View {
        GeometryReader { geometry in
            let size = screen.landscapeSize
            let scale = geometry.size.width / size.width
            ZStack {
                Color.black
                // 居中的 16:9 画面，两侧是黑边，和真实全屏播放一样。
                LinearGradient(colors: [Color(red: 0.35, green: 0.3, blue: 0.75), Color(red: 0.1, green: 0.45, blue: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: size.height * 16 / 9, height: size.height)
                PlayerGlassChrome(
                    title: "示例视频标题",
                    videoQualityControl: PlayerQualityControl(title: "1080P", accessibilityLabel: "分辨率", options: [],
                                                             selectedID: 0, isEnabled: true, onSelect: { _ in }),
                    audioQualityControl: PlayerQualityControl(title: "192K", accessibilityLabel: "音质", options: [],
                                                             selectedID: 0, isEnabled: true, onSelect: { _ in }),
                    position: 83, duration: 300, buffered: 120,
                    isPlaying: true, canControlPlayback: true, isFullScreen: true,
                    safeAreaInsets: EdgeInsets(top: 0, leading: screen.landscapeSideInset,
                                               bottom: 21, trailing: screen.landscapeSideInset),
                    isDanmakuEnabled: true, showsDanmakuToggle: true, onToggleDanmaku: {},
                    onSendDanmaku: {}
                ) { EmptyView() }
                if screen.hasDynamicIsland {
                    // 横屏时灵动岛在一侧的中间。
                    // 画在黑边上看不见，加一圈淡描边示意位置。
                    Capsule()
                        .fill(.black)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1.5) }
                        .frame(width: 37, height: 126)
                        .position(x: 11 + 37 / 2, y: size.height / 2)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: screen.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: screen.cornerRadius, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1 / max(scale, 0.01))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("全屏控件位置预览")
        }
        .aspectRatio(screen.landscapeSize.width / screen.landscapeSize.height, contentMode: .fit)
    }
}
