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
    @State private var serviceSheet: MineService?


    var body: some View {
        NavigationStack {
            Group {
                if let profile = account.profile {
                    loggedInView(profile)
                } else if account.isRestoringSession {
                    LoadingTaskAnchor()
                } else if account.isLoggedIn {
                    ContentUnavailableView {
                        Label("账号信息暂未加载", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(account.sessionError ?? "登录信息已保留，可以重试加载。")
                    } actions: {
                        Button("重试") { Task { await account.refreshProfile() } }
                            .disabled(account.isRefreshingProfile)
                        Button("退出登录", role: .destructive) { Task { await account.logout() } }
                    }
                } else {
                    loggedOutView
                }
            }
            // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触入口行。
            .leftEdgeTapDeadZone()
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("我的")
        }
        .sheet(item: $serviceSheet, onDismiss: {
            nowPlaying.isServiceSheetPresented = false
        }) { service in
            MineServiceSheet(service: service)
                .appTextSize()
        }
        .onChange(of: account.sessionID) { serviceSheet = nil }
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
            if let message = account.sessionError {
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("重新连接") { Task { await account.refreshProfile() } }
                        .disabled(account.isRefreshingProfile)
                }
            }
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
                    service: .favorites
                )
                serviceRow(
                    icon: "clock.arrow.circlepath",
                    color: .blue,
                    title: "历史记录",
                    service: .history
                )
                serviceRow(
                    icon: "flag.checkered",
                    color: .pink,
                    title: "稍后再看",
                    service: .watchLater
                )
            } header: {
                Text("我的服务")
            }

            Section {
                serviceRow(
                    icon: "gearshape.fill",
                    color: .gray,
                    title: "系统设置",
                    service: .settings
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
    private func serviceRow(
        icon: String,
        color: Color,
        title: String,
        service: MineService
    ) -> some View {
        Button {
            nowPlaying.isServiceSheetPresented = true
            serviceSheet = service
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

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
    }
}
