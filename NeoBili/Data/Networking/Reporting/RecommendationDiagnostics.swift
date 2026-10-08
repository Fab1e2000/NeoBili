import Foundation

/// Local experiment preferences never replace the application's own identity.
enum RecommendationExperiment {
    static let buvidKey = DiagnosticsPreferences.buvidKey
    static let loggingKey = DiagnosticsPreferences.loggingKey

    static func configure(environment: [String: String], defaults: UserDefaults = .standard) {
        #if DEBUG
        guard !AppNetwork.isRegression else { return }
        if let value = environment["NEOBILI_EXPERIMENT_BUVID"],
           (16...128).contains(value.count), value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
            defaults.set(value, forKey: buvidKey)
        }
        if environment["NEOBILI_RECOMMENDATION_LOGGING"] == "1" {
            defaults.set(true, forKey: loggingKey)
        }
        #endif
    }
}

/// Stores only explicitly selected diagnostic fields. Credentials and raw payloads never reach disk.
actor RecommendationDiagnostics {
    static let shared = RecommendationDiagnostics()
    private let directory: URL
    private let limit: Int
    private let enabled: @Sendable () -> Bool
    private var writeFailed = false
    private static let paths: Set<String> = [
        "/x/v2/feed/index", "/x/web-interface/wbi/index/top/feed/rcmd",
        "/bilibili.app.viewunite.v1.View/View", "/bilibili.app.viewunite.v1.View/RelatesFeed",
        "/x/report/heartbeat/mobile", "/x/v2/history/report", "/x/click-interface/web/heartbeat",
        "/log/pbmobile/unrealtime"
    ]
    private static let parameters: Set<String> = [
        "flush", "pull", "idx", "build", "mobi_app", "platform", "device", "lang", "locale",
        "fnval", "open_event", "openevent", "login_event", "auto_refresh_state", "aid", "cid", "bvid",
        "played_time", "realtime", "start_ts", "type", "dt", "play_type", "from", "spmid", "from_spmid",
        "actionKey", "screen", "network", "qn", "progress", "c_locale", "s_locale", "column",
        "inline_sound", "inline_sound_cold_state", "autoplay_card", "video_mode", "inline_danmu",
        "client_attr", "qn_policy", "player_net", "guidance", "soft_fnval", "teenagers_age", "fnver",
        "force_host", "https_url_req", "voice_balance", "disable_rcmd", "recsys_mode", "fourk"
    ]
    init(directory: URL? = nil, limit: Int = 2 * 1024 * 1024,
         enabled: @escaping @Sendable () -> Bool = {
             #if DEBUG
             !AppNetwork.isRegression && UserDefaults.standard.bool(forKey: RecommendationExperiment.loggingKey)
             #else
             false
             #endif
         }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecommendationDiagnostics", isDirectory: true)
        self.limit = limit
        self.enabled = enabled
    }
    func begin(_ request: URLRequest, attempt: Int) -> String? {
        guard enabled(), let url = request.url, Self.paths.contains(url.path),
              url.host == "app.bilibili.com" || url.host == "api.bilibili.com" || url.host == "grpc.biliapi.net" || url.host == "dataflow.biliapi.com" else { return nil }
        let id = UUID().uuidString
        var fields: [String: String] = [:]
        var items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded", let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            items += URLComponents(string: "https://local.invalid/?" + text)?.queryItems ?? []
        }
        for item in items where Self.parameters.contains(item.name) {
            if let value = item.value, value.count <= 160,
               value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-,:/".contains($0)) }) {
                fields[item.name] = value
            }
        }
        append(["id": id, "phase": "request", "host": url.host ?? "", "path": url.path,
                "method": request.httpMethod ?? "GET", "attempt": attempt, "parameters": fields,
                "has_banner_hash": items.contains { $0.name == "banner_hash" && $0.value?.isEmpty == false },
                "has_access_key": request.value(forHTTPHeaderField: "authorization") != nil || items.contains { $0.name == "access_key" && $0.value?.isEmpty == false },
                "has_cookie": request.value(forHTTPHeaderField: "Cookie") != nil,
                "has_ticket": request.value(forHTTPHeaderField: "x-bili-ticket") != nil,
                "has_buvid": request.value(forHTTPHeaderField: "buvid") != nil])
        return id
    }
    func finish(_ id: String?, data: Data, response: URLResponse) {
        guard let id else { return }
        var entry: [String: Any] = ["id": id, "phase": "response", "bytes": data.count,
                                  "status": (response as? HTTPURLResponse)?.statusCode ?? -1]
        if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            entry["api_code"] = json["code"] as? Int
            let payload = json["data"] as? [String: Any]
            let cards = (payload?["items"] ?? payload?["item"]) as? [[String: Any]] ?? []
            entry["cards"] = cards.prefix(100).map { card in
                var safe: [String: Any] = [:]
                for key in ["title", "goto", "card_goto", "bvid", "param", "idx"] {
                    if let value = card[key] as? String {
                        if key == "param" && !value.allSatisfy(\.isNumber) { continue }
                        safe[key] = String(value.prefix(300))
                    }
                    else if let value = card[key] as? Int { safe[key] = value }
                }
                return safe
            }
        }
        append(entry)
    }
    func fail(_ id: String?, error: Error) {
        guard let id else { return }
        append(["id": id, "phase": "transport_error", "code": (error as NSError).code])
    }
    private func append(_ fields: [String: Any]) {
        do {
            var fields = fields
            fields["time"] = ISO8601DateFormatter().string(from: Date())
            var data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            data.append(10)
            guard data.count <= limit else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            let current = directory.appendingPathComponent("current.jsonl")
            let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size + data.count > limit {
                let oldest = directory.appendingPathComponent("3.jsonl")
                if FileManager.default.fileExists(atPath: oldest.path) { try FileManager.default.removeItem(at: oldest) }
                for index in stride(from: 2, through: 0, by: -1) {
                    let source = directory.appendingPathComponent(index == 0 ? "current.jsonl" : "\(index).jsonl")
                    if FileManager.default.fileExists(atPath: source.path) {
                        try FileManager.default.moveItem(at: source, to: directory.appendingPathComponent("\(index + 1).jsonl"))
                    }
                }
            }
            if !FileManager.default.fileExists(atPath: current.path) { FileManager.default.createFile(atPath: current.path, contents: nil) }
            let file = try FileHandle(forWritingTo: current)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
            writeFailed = false
        } catch { writeFailed = true }
    }
    func export() throws -> URL {
        if writeFailed { throw CocoaError(.fileWriteUnknown) }
        var combined = Data()
        for name in ["3.jsonl", "2.jsonl", "1.jsonl", "current.jsonl"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { combined.append(try Data(contentsOf: url)) }
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("NeoBili-recommendation-log.jsonl")
        try combined.write(to: output, options: .atomic)
        return output
    }
}
