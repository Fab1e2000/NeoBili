import SwiftUI
import UIKit

struct FollowingSidebarAvatar: View {
    @Environment(\.appThemeColor) private var themeColor
    let item: FollowingSelection
    let selected: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if let up = item.up {
                BiliImage(url: up.secureAvatarURL).aspectRatio(contentMode: .fill).id(up.mid)
            } else {
                AllDynamicsAvatar()
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .overlay { Circle().stroke(selected ? themeColor : .white.opacity(0.4), lineWidth: selected ? 2.5 : 1) }
        .overlay(alignment: .topTrailing) {
            if item.up?.hasUpdate == true {
                Circle().fill(.red).frame(width: 10, height: 10)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
            }
        }
        .overlay(alignment: .bottom) {
            if item.up?.liveRoomID != nil {
                Text("LIVE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(themeColor, in: Capsule())
                    .offset(y: 6)
            }
        }
        .scaleEffect(size / 60)
        .frame(width: size, height: size)
        .padding(.bottom, item.up?.liveRoomID != nil ? size / 10 : 0)
        .appTheme()
    }
}

/// 「全部动态」使用的代码原生品牌头像：三条轨道与节点表示多个 UP
/// 共同组成一条动态流，不依赖额外位图资源。
struct AllDynamicsAvatar: View {
    @Environment(\.appThemeColor) private var themeColor
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [themeColor, themeColor.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                orbit(width: 40, height: 17, rotation: 24)
                orbit(width: 40, height: 17, rotation: -24)
                orbit(width: 20, height: 39, rotation: 0)

                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)

                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .offset(x: 17, y: -7)

                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: -14, y: 11)
            }
        }
    }

    private func orbit(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        Ellipse()
            .stroke(.white.opacity(0.82), lineWidth: 1.6)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
    }
}
