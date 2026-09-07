import SwiftUI

enum PlayerGestureSettings {
    static let leftKey = "neobili.playerGesture.leftBoundary"
    static let rightKey = "neobili.playerGesture.rightBoundary"
    static let reverseKey = "neobili.playerGesture.reverseVertical"
    static func boundaries(left: Double, right: Double) -> (Double, Double) {
        let first = min(max(left.isFinite ? left : 0.33, 0.1), 0.75)
        let second = min(max(right.isFinite ? right : 0.67, first + 0.15), 0.9)
        return (first, second)
    }
}

struct PlayerGestureSettingsSection: View {
    @AppStorage(PlayerGestureSettings.leftKey) private var left = 0.33
    @AppStorage(PlayerGestureSettings.rightKey) private var right = 0.67
    @AppStorage(PlayerGestureSettings.reverseKey) private var reversed = false
    @State private var fullscreenPreview = false

    private var boundaries: (Double, Double) { PlayerGestureSettings.boundaries(left: left, right: right) }

    var body: some View {
        Section {
            Toggle("全屏比例预览", isOn: $fullscreenPreview)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    zone("亮度", symbol: "sun.max", color: .orange)
                        .frame(width: geometry.size.width * boundaries.0)
                    zone(fullscreenPreview ? "退出全屏" : "进入全屏", symbol: "arrow.up.and.down", color: .gray)
                        .frame(width: geometry.size.width * (boundaries.1 - boundaries.0))
                    zone("音量", symbol: "speaker.wave.2", color: .blue)
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white).frame(width: 2).offset(x: geometry.size.width * boundaries.0 - 1)
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white).frame(width: 2).offset(x: geometry.size.width * boundaries.1 - 1)
                }
            }
            .aspectRatio(fullscreenPreview ? 2.16 : 16.0 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("左侧亮度、中部全屏、右侧音量。分界为宽度的\(Int(boundaries.0 * 100))%与\(Int(boundaries.1 * 100))%")

            boundarySlider("左侧分界", value: Binding(get: { boundaries.0 }, set: { left = $0 }),
                           range: 0.1...(boundaries.1 - 0.15))
            boundarySlider("右侧分界", value: Binding(get: { boundaries.1 }, set: { right = $0 }),
                           range: (boundaries.0 + 0.15)...0.9)
            Toggle("反转上下滑", isOn: $reversed)
            Button("恢复默认分区") { left = 0.33; right = 0.67; reversed = false }
        } header: {
            Text("播放器滑动手势")
        } footer: {
            Text(reversed
                 ? "左侧下滑增加亮度，右侧下滑增加音量；中部下滑进入全屏，全屏中部上滑退出。横滑调整进度，松手跳转，滑到上方两角可取消。"
                 : "左侧上滑增加亮度，右侧上滑增加音量；中部上滑进入全屏，全屏中部下滑退出。横滑整屏对应 90 秒，松手跳转，滑到上方两角可取消。")
        }
    }

    private func zone(_ title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color.opacity(0.65).background(.black))
    }

    private func boundarySlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.01)
                .accessibilityLabel(title)
        }
    }
}
