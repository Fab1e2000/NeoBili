import Foundation
import SwiftUI

/// `getDanmuInfo` 的响应形状：认证 token 与候选弹幕服务器（wss 端口优先）。
struct LiveDanmuInfoPayload: Decodable {
    let token: String
    let hosts: [Host]

    struct Host: Decodable {
        let host: String
        let wssPort: Int
        enum CodingKeys: String, CodingKey { case host; case wssPort = "wss_port" }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        token = values.liveString("token") ?? ""
        hosts = (try? values.decode([Host].self, forKey: LiveCodingKey("host_list"))) ?? []
    }
}
