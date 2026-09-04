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
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("我的")
        }
        .sheet(item: $loginSheet) { sheet in
            switch sheet {
            case .qr: QRLoginSheet()
            case .password: PasswordLoginSheet()
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
                profileHeader(profile)
            }

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

    private func profileHeader(_ profile: AccountStore.Profile) -> some View {
        HStack(spacing: 14) {
            BiliImage(url: profile.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if profile.isVIP {
                        Text("大会员")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.98, green: 0.45, blue: 0.09), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 8) {
                    Text("LV\(profile.level)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .systemGray), in: RoundedRectangle(cornerRadius: 4))

                    Label(String(format: "%.1f", profile.coins), systemImage: "centsign.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
