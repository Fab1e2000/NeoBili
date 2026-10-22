import Foundation

/// `getDanmuInfo` 的响应形状：认证 token 与候选弹幕服务器（wss 端口优先）。
public struct LiveDanmuInfoPayload: Decodable {
    public let token: String
    public let hosts: [Host]

    public struct Host: Decodable {
        public let host: String
        public let wssPort: Int
        enum CodingKeys: String, CodingKey { case host; case wssPort = "wss_port" }
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        token = values.liveString("token") ?? ""
        hosts = (try? values.decode([Host].self, forKey: LiveCodingKey("host_list"))) ?? []
    }
}
