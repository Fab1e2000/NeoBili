import SwiftUI

struct RecommendationDiagnosticsView: View {
    @AppStorage(RecommendationExperiment.loggingKey) private var enabled = false
    @AppStorage(RecommendationExperiment.buvidKey) private var override = ""
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Toggle("记录推荐与观看日志", isOn: $enabled)
                LabeledContent("设备名牌", value: override.isEmpty
                               ? String(localized: "NeoBili 自身编号")
                               : String(localized: "官方编号（本地测试）"))
                if !override.isEmpty {
                    Button("恢复 NeoBili 自身编号") { override = "" }
                }
            } footer: {
                Text("日志保存在手机上，最多约 8 MB。记录请求参数、返回的视频及观看上报结果，隐藏登录凭据和设备编号。")
            }
            Section {
                Button("准备导出日志") {
                    exporting = true; failed = false; exportURL = nil
                    Task {
                        do { exportURL = try await RecommendationDiagnostics.shared.export() }
                        catch { failed = true }
                        exporting = false
                    }
                }
                .disabled(exporting)
                if exporting { ProgressView() }
                if let exportURL { ShareLink("分享日志文件", item: exportURL) }
                if failed { Text("日志导出失败，请重试。").foregroundStyle(.red) }
            } footer: {
                Text("日志含观看内容和操作时间，仅分享给你信任的人。")
            }
        }
        .settingsPage("推荐实验日志")
    }
}
