import SwiftUI

struct ThemeSettingsView: View {
    @Environment(\.appThemeColor) private var themeColor
    @Environment(ThemeIconController.self) private var themeIcon
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    private let columns = [GridItem(.adaptive(minimum: 82), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("当前主题 · \(AppTheme.selected(themeID).name)")
                        .font(.headline)
                    HStack {
                        Label("主题预览", systemImage: "heart.fill")
                            .foregroundStyle(themeColor)
                        Spacer()
                        Text("已应用")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(themeColor)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(themeColor.opacity(0.14), in: Capsule())
                    }
                    Text("用于底部标签栏、自定义图标及自定义装饰。系统控件的文字和图标跟随浅色／深色外观。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(18)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                if let message = themeIcon.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Button("重试更新桌面图标") {
                            Task { await themeIcon.apply(themeID: themeID) }
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppTheme.presets) { theme in
                        Button {
                            themeID = theme.id
                        } label: {
                            VStack(spacing: 8) {
                                Circle().fill(theme.color)
                                    .frame(width: 48, height: 48)
                                    .overlay {
                                        if theme.id == AppTheme.selected(themeID).id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.primary)
                                                .padding(7)
                                                .background(Color(uiColor: .systemBackground), in: Circle())
                                        }
                                    }
                                Text(theme.name).font(.caption).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 82)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(theme.name)
                        .accessibilityAddTraits(theme.id == AppTheme.selected(themeID).id ? [.isSelected] : [])
                        .accessibilityIdentifier("theme.\(theme.id)")
                    }
                }
                Button("恢复默认樱花粉") { themeID = AppTheme.defaultID }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("主题色")
        .navigationBarTitleDisplayMode(.inline)
        .appTheme()
    }
}
