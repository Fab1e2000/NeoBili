import NeoBiliDomain
import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppUpdateStore.self) private var appUpdate: AppUpdateStore?
    @State private var showingUpdateSheet = false

    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: appVersion)
                LabeledContent("播放内核", value: "mpv (MPVKit)")
                LabeledContent("接口与交互参考", value: "PiliPlus / MeloX")
            }

            if let store = appUpdate {
                updateSection(store)
            }
        }
        .settingsPage("关于")
        .sheet(isPresented: $showingUpdateSheet) {
            if let store = appUpdate {
                AppUpdateSheet(store: store)
                    .appTextSize()
            }
        }
    }

    @ViewBuilder
    private func updateSection(_ store: AppUpdateStore) -> some View {
        Section("应用更新") {
            Toggle(
                "自动检查更新",
                isOn: Binding(
                    get: { store.autoCheckEnabled },
                    set: { store.autoCheckEnabled = $0 }
                )
            )
            .accessibilityIdentifier("about.autoCheckUpdate")

            if let release = store.availableRelease {
                Button {
                    showingUpdateSheet = true
                } label: {
                    LabeledContent("发现新版本") {
                        HStack(spacing: 6) {
                            if store.showsUpdateBadge {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                            }
                            Text("v\(release.version)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("about.availableUpdate")
            }

            Button {
                Task { await store.checkManually() }
            } label: {
                LabeledContent("检查更新") {
                    checkStatusView(store)
                }
            }
            .foregroundStyle(.primary)
            .disabled(store.checkState == .checking)
            .accessibilityIdentifier("about.checkUpdate")

            if case .failed(let message) = store.checkState {
                Text(message)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func checkStatusView(_ store: AppUpdateStore) -> some View {
        switch store.checkState {
        case .idle:
            Text("立即检查")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                Text("正在检查")
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            Text("已是最新版本")
                .foregroundStyle(.secondary)
        case .available:
            Text("重新检查")
                .foregroundStyle(.secondary)
        case .failed:
            Text("重试")
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let short = appUpdate?.currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
