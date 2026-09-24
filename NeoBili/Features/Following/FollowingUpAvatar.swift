import SwiftUI

/// 头像条与「全部关注」共用的圆形头像：选中描主题色环，未读标红点，开播标 LIVE。
struct FollowingUpAvatar: View {
    @Environment(\.appThemeColor) private var themeColor
    let item: FollowingSelection
    var selected = false
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            if let up = item.up {
                BiliImage(url: up.secureAvatarURL).aspectRatio(contentMode: .fill).id(up.mid)
            } else {
                // 品牌头像按 60pt 绘制，再等比缩放到当前尺寸。
                AllDynamicsAvatar().frame(width: 60, height: 60).scaleEffect(size / 60)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        // 选中环画在头像外侧并留一圈间隙，不压住头像本身。
        .padding(3)
        .overlay {
            if selected { Circle().strokeBorder(themeColor, lineWidth: 2) }
        }
        .overlay(alignment: .topTrailing) {
            if item.up?.hasUpdate == true, item.up?.liveRoomID == nil {
                Circle().fill(.red).frame(width: 10, height: 10)
                    .overlay { Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 2) }
                    .offset(x: -3, y: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if item.up?.liveRoomID != nil {
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(themeColor, in: Capsule())
                    .overlay { Capsule().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 1.5) }
                    .offset(y: 3)
            }
        }
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
