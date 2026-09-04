import SwiftUI

/// 「我的」Tab。未登录时给登录入口，登录后展示个人信息与收藏、历史、
/// 稍后再看、系统设置等入口。
struct MineView: View {
    @Environment(AccountStore.self) private var account
    @Environment(NowPlayingStore.self) private var nowPlaying

    private enum LoginSheet: String, Identifiable {
        case qr
        case password

        var id: String { rawValue }
    }

    @State private var loginSheet: LoginSheet?

    var body: some View {
        NavigationStack {
            Group {
                if let profile = account.profile {
                    loggedInView(profile)
                } else if account.isRestoringSession {
                    ProgressView("正在检查登录状态…")
                } else {
                    loggedOutView
                }
            }
            // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触入口行。
            .leftEdgeTapDeadZone()
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("我的")
        }
        .sheet(item: $loginSheet) { sheet in
            switch sheet {
            // sheet 有自己的 UIHostingController，文字档位要在根部重新注入。
            case .qr: QRLoginSheet().appTextSize()
            case .password: PasswordLoginSheet().appTextSize()
            }
        }
    }

    // MARK: - 未登录

    private var loggedOutView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)

            Text("尚未登录")
                .font(.title3.weight(.semibold))

            Text("登录后可以使用收藏、历史、稍后再看，\n首页也会变成属于你的个性化推荐。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("扫码登录") { loginSheet = .qr }
                    .buttonStyle(.borderedProminent)
                Button("账号密码登录") { loginSheet = .password }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 已登录

    private func loggedInView(_ profile: AccountStore.Profile) -> some View {
        List {
            Section {
                profileCard(profile)
            }
            // 头部是一张自己排版的卡片，不该套 List 行那套内边距、分隔线和
            // 点按高亮，所以把行样式整个撤掉，由卡片自己决定留白。
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                serviceRow(
                    icon: "star.fill",
                    color: .orange,
                    title: "收藏",
                    destination: { FavoritesView() }
                )
                serviceRow(
                    icon: "clock.arrow.circlepath",
                    color: .blue,
                    title: "历史记录",
                    destination: { HistoryView() }
                )
                serviceRow(
                    icon: "flag.checkered",
                    color: .pink,
                    title: "稍后再看",
                    destination: { WatchLaterView() }
                )
            } header: {
                Text("我的服务")
            }

            Section {
                serviceRow(
                    icon: "gearshape.fill",
                    color: .gray,
                    title: "系统设置",
                    destination: { SettingsView() }
                )
            }
        }
    }

    /// 个人信息卡片。
    ///
    /// 头像居中放大、名字单独占一行，等级 / 大会员 / 硬币收成一排 chip 摆在下面。
    /// 之前是「左头像 + 右两行」的列表行样式：名字要和大会员徽章抢同一行的宽度，
    /// 名字一长就被压缩，等级和硬币又挤在第二行，几种字号和圆角混在一起。
    /// 竖排之后每一层只承担一件事，长名字也不会挤到徽章。
    private func profileCard(_ profile: AccountStore.Profile) -> some View {
        VStack(spacing: 12) {
            BiliImage(url: profile.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                }

            Text(profile.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 8) {
                badge("LV\(profile.level)", background: Color(uiColor: .systemGray))

                if profile.isVIP {
                    badge("大会员", background: Color(red: 0.98, green: 0.45, blue: 0.09))
                }

                badge(
                    String(format: "%.1f 硬币", profile.coins),
                    background: Color(uiColor: .tertiarySystemFill),
                    foreground: .secondary
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    /// 卡片下方那排小标签。三个徽章共用同一套字号、内边距和圆角，
    /// 高度才会一致——原来等级和大会员是两套数值，并排时上下差半格。
    private func badge(
        _ text: String,
        background: Color,
        foreground: Color = .white
    ) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    /// Apple Music 式的服务入口行：圆角彩色底 + SF Symbol + 标题。
    private func serviceRow<Destination: View>(
        icon: String,
        color: Color,
        title: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 2)
        }
    }
}
