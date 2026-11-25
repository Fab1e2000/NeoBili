import NeoBiliDomain
import SwiftUI
import UIKit

/// 新版本详情与安装入口页：支持唤起 SideStore/AltStore（方案 1）与下载 IPA 分享给签名工具（方案 2）。
struct AppUpdateSheet: View {
    let store: AppUpdateStore
    @Environment(\.dismiss) private var dismiss
    @State private var sharePackageItem: ShareablePackage?
    @State private var installerLaunchFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let release = store.availableRelease {
                    content(for: release)
                } else {
                    ContentUnavailableView(
                        "暂无可用更新",
                        systemImage: "checkmark.circle",
                        description: Text("当前版本已是最新。")
                    )
                }
            }
            .navigationTitle("发现新版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .onChange(of: store.downloadState) { _, state in
            if case .readyToShare(let fileURL) = state {
                sharePackageItem = ShareablePackage(url: fileURL)
            }
        }
        .sheet(item: $sharePackageItem, onDismiss: {
            store.finishSharingPackage()
        }) { item in
            PackageShareSheet(fileURL: item.url)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(for release: AppUpdateRelease) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard(for: release)

                if !release.releaseNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("更新内容")
                            .font(.app(.headline, weight: .semibold))
                        Text(release.releaseNotes)
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                actionsSection(for: release)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func headerCard(for release: AppUpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("NeoBili v\(release.version)")
                    .font(.app(.title2, weight: .bold))
                Spacer(minLength: 0)
                Text("当前 v\(store.currentVersion)")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let date = release.releaseDate {
                    Label(Self.dateFormatter.string(from: date), systemImage: "calendar")
                }
                if let size = release.packageSize, size > 0 {
                    Label(Self.byteFormatter.string(fromByteCount: size), systemImage: "arrow.down.doc")
                }
            }
            .font(.app(.footnote))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private func actionsSection(for release: AppUpdateRelease) -> some View {
        VStack(spacing: 12) {
            if let installer = store.installedInstaller {
                Menu {
                    Button {
                        launchInstaller(installer, source: .github)
                    } label: {
                        Label("GitHub Releases（默认）", systemImage: "arrow.down.circle")
                    }
                    Button {
                        launchInstaller(installer, source: .mirror)
                    } label: {
                        Label("镜像源（n015.top）", systemImage: "server.rack")
                    }
                    Divider()
                    Button {
                        launchInstaller(installer, source: nil)
                    } label: {
                        Label("打开软件源页面", systemImage: "square.stack")
                    }
                } label: {
                    Label(
                        String(localized: "在 \(installer.displayName) 中更新"),
                        systemImage: "arrow.down.app"
                    )
                    .font(.app(.headline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("updateSheet.openInstaller")
            }

            downloadControl(isPrimary: store.installedInstaller == nil)

            if installerLaunchFailed {
                Text("未能打开签名工具，请先确认已安装对应应用，或直接下载 IPA 分享。")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 16) {
                Button("前往 GitHub Releases") {
                    Task { await store.openGitHubReleases() }
                }
                .font(.app(.footnote))
                .accessibilityIdentifier("updateSheet.openGitHub")

                Spacer(minLength: 0)

                if store.isAvailableVersionIgnored {
                    Button("取消忽略此版本") {
                        store.clearIgnoredVersion()
                    }
                    .font(.app(.footnote))
                    .accessibilityIdentifier("updateSheet.unignore")
                } else {
                    Button("忽略此版本") {
                        store.ignoreAvailableVersion()
                        dismiss()
                    }
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("updateSheet.ignore")
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func downloadControl(isPrimary: Bool) -> some View {
        switch store.downloadState {
        case .idle, .readyToShare:
            downloadButton(title: String(localized: "下载 IPA 并分享到签名工具"), isPrimary: isPrimary)
        case .downloading(let progress, let completedBytes, let totalBytes):
            VStack(spacing: 10) {
                if totalBytes > 0 {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
                HStack {
                    Text(downloadProgressText(completedBytes: completedBytes, totalBytes: totalBytes))
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Button("取消下载", role: .destructive) {
                        store.cancelDownload()
                    }
                    .font(.app(.footnote, weight: .medium))
                    .accessibilityIdentifier("updateSheet.cancelDownload")
                }
            }
            .padding(14)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.app(.footnote))
                    .foregroundStyle(.red)
                downloadButton(title: String(localized: "重新下载 IPA"), isPrimary: isPrimary)
            }
        }
    }

    @ViewBuilder
    private func downloadButton(title: String, isPrimary: Bool) -> some View {
        if isPrimary {
            Menu {
                downloadSourceMenuItems
            } label: {
                Label(title, systemImage: "square.and.arrow.down")
                    .font(.app(.headline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("updateSheet.downloadIPA")
        } else {
            Menu {
                downloadSourceMenuItems
            } label: {
                Label(title, systemImage: "square.and.arrow.down")
                    .font(.app(.subheadline, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("updateSheet.downloadIPA")
        }
    }

    @ViewBuilder
    private var downloadSourceMenuItems: some View {
        Button {
            store.startDownload(source: .github)
        } label: {
            Label("GitHub Releases（默认）", systemImage: "arrow.down.circle")
        }
        Button {
            store.startDownload(source: .mirror)
        } label: {
            Label("镜像源（n015.top）", systemImage: "server.rack")
        }
    }

    private func launchInstaller(_ installer: AppUpdateStore.ExternalInstaller, source: AppUpdateDownloadSource?) {
        installerLaunchFailed = false
        Task {
            let opened = await store.openInInstaller(installer, source: source)
            if !opened { installerLaunchFailed = true }
        }
    }

    private func downloadProgressText(completedBytes: Int64, totalBytes: Int64) -> String {
        let sourceLabel = store.activeDownloadSource == .github
            ? "GitHub"
            : String(localized: "镜像源")
        let completed = Self.byteFormatter.string(fromByteCount: completedBytes)
        if totalBytes > 0 {
            let total = Self.byteFormatter.string(fromByteCount: totalBytes)
            return "\(sourceLabel) · \(completed) / \(total)"
        }
        return "\(sourceLabel) · \(String(localized: "已下载 \(completed)"))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

private struct ShareablePackage: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PackageShareSheet: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
