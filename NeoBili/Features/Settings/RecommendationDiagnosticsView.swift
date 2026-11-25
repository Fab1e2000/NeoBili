import NeoBiliDomain
import SwiftUI

struct RecommendationDiagnosticsView: View {
    @Environment(\.applicationServices) private var services
    @AppStorage(DiagnosticsPreferences.loggingKey) private var enabled = false
    @AppStorage(DiagnosticsPreferences.buvidKey) private var override = ""
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
            }
            Section {
                Button("准备导出日志") {
                    exporting = true; failed = false; exportURL = nil
                    Task {
                        do { exportURL = try await services.exportDiagnostics() }
                        catch { failed = true }
                        exporting = false
                    }
                }
                .disabled(exporting)
                if exporting { ProgressView() }
                if let exportURL { ShareLink("分享日志文件", item: exportURL) }
                if failed { Text("日志导出失败，请重试。").foregroundStyle(.red) }
            }
        }
        .settingsPage("推荐实验日志")
    }
}
