import XCTest
@testable import NeoBili

final class RecommendationDiagnosticsTests: XCTestCase {
    func testLogsSurviveReopeningAndExcludeCredentials() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let logger = RecommendationDiagnostics(directory: folder, enabled: { true })
        var request = URLRequest(url: URL(string: "https://app.bilibili.com/x/v2/feed/index?flush=6&access_key=SECRET_TOKEN&sign=SECRET_SIGN&track_id=SECRET_TRACK")!)
        request.setValue("SECRET_COOKIE", forHTTPHeaderField: "Cookie")
        request.setValue("SECRET_DEVICE", forHTTPHeaderField: "buvid")
        let id = await logger.begin(request, attempt: 0)
        XCTAssertNotNil(id)
        let body = Data(#"{"code":0,"data":{"items":[{"title":"ASMR 示例","param":"123"}],"ticket":"SECRET_RESPONSE"}}"#.utf8)
        await logger.finish(id, data: body, response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        let reopened = RecommendationDiagnostics(directory: folder, enabled: { true })
        let url = try await reopened.export()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET"))
        XCTAssertTrue(text.contains("ASMR 示例"))
        XCTAssertTrue(text.contains("\"flush\":\"6\""))
        XCTAssertTrue(text.contains("response"))
    }

    func testDisabledAndUnrelatedTrafficDoNotWrite() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = RecommendationDiagnostics(directory: folder, enabled: { false })
        let id = await logger.begin(URLRequest(url: URL(string: "https://app.bilibili.com/x/v2/feed/index")!), attempt: 0)
        XCTAssertNil(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        let enabled = RecommendationDiagnostics(directory: folder, enabled: { true })
        let unrelated = await enabled.begin(URLRequest(url: URL(string: "https://example.com/x/v2/feed/index")!), attempt: 0)
        XCTAssertNil(unrelated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testRotationBoundsDiskUsage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let logger = RecommendationDiagnostics(directory: folder, limit: 800, enabled: { true })
        for _ in 0..<30 {
            _ = await logger.begin(URLRequest(url: URL(string: "https://app.bilibili.com/x/v2/feed/index?flush=6")!), attempt: 0)
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertLessThanOrEqual(files.count, 4)
        for file in files { XCTAssertLessThanOrEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 800) }
    }
}
