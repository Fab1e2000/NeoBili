import SwiftUI

struct InteractionSettingsView: View {
    @Environment(\.appThemeColor) private var themeColor
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(LeftEdgeTapDeadZone.storageKey) private var deadZoneWidth = LeftEdgeTapDeadZone.defaultWidth
    @State private var showsDeadZonePreview = false
    @State private var previewHideTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("下拉刷新距离", value: "\(Int(HomeRefreshSettings.clamped(refreshDistance))) pt")
                        .monospacedDigit()
                    Slider(value: $refreshDistance, in: HomeRefreshSettings.range, step: 5)
                        .accessibilityLabel("下拉刷新距离")
                        .accessibilityValue(String(localized: "\(Int(refreshDistance)) 点"))
                }
            } header: {
                Text("滚动")
            } footer: {
                Text("推荐、直播和关注页共用。距离越短，越容易触发刷新。")
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("左缘触控死区", value: "\(Int(deadZoneWidth)) pt")
                        .monospacedDigit()
                    // set 必须写成闭包：直接传方法引用 `set: updateDeadZone` 会让
                    // Xcode 26.2 的编译器在生成 IR 时崩溃。
                    Slider(value: Binding(get: { deadZoneWidth }, set: { updateDeadZone($0) }),
                           in: 0...LeftEdgeTapDeadZone.maxWidth, step: 1)
                        .accessibilityLabel("左缘触控死区宽度")
                        .accessibilityValue(String(localized: "\(Int(deadZoneWidth)) 点"))
                }
            } header: {
                Text("防误触")
            } footer: {
                Text("屏幕左缘这一窄条内的点按不生效，避免侧滑返回时误点到卡片。拖动滑杆时会高亮显示范围。")
            }
        }
        .settingsPage("滚动与防误触")
        .overlay(alignment: .leading) {
            if showsDeadZonePreview {
                Rectangle()
                    .fill(themeColor.opacity(0.22))
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(themeColor.opacity(0.85)).frame(width: 1.5)
                    }
                    .frame(width: deadZoneWidth)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDisappear { previewHideTask?.cancel() }
    }

    private func updateDeadZone(_ value: Double) {
        deadZoneWidth = value.rounded()
        if !showsDeadZonePreview {
            withAnimation(.easeOut(duration: 0.15)) { showsDeadZonePreview = true }
        }
        previewHideTask?.cancel()
        previewHideTask = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            withAnimation(.easeIn(duration: 0.45)) { showsDeadZonePreview = false }
        }
    }
}
