import Foundation

/// 使用服务端原地址。直连 FLV 避免等待 HLS 的播放列表和分片，AVC 保持硬解兼容。
/// 与 PiliPlus 一样不把 HLS 强制放在所有直播协议之前，并留出另一协议的回退机会。
enum LiveStreamStartupPolicy {
    static func candidates(from candidates: [LiveStreamCandidate]) -> [LiveStreamCandidate] {
        var seen = Set<URL>()
        let ordered = candidates.enumerated().filter { seen.insert($0.element.url).inserted }.sorted {
            let lhs = priority($0.element), rhs = priority($1.element)
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
        guard let first = ordered.first else { return [] }
        var result = [first]
        // 首线路卡住时先换协议，防止 4 个备用名额全被同一格式的 CDN 占据。
        if let alternate = ordered.dropFirst().first(where: {
            $0.isHLS != first.isHLS && $0.codecName == "avc"
        }) {
            result.append(alternate)
        }
        for candidate in ordered.dropFirst() where !result.contains(candidate) {
            guard result.count < 4 else { break }
            result.append(candidate)
        }
        return result
    }

    private static func priority(_ candidate: LiveStreamCandidate) -> Int {
        let codec = candidate.codecName == "avc" ? 0 : candidate.codecName == "hevc" ? 20 : 40
        let protocolCost = candidate.protocolName == "http_stream" && candidate.formatName == "flv" ? 0 : 10
        return codec + protocolCost + (candidate.formatName == "fmp4" ? 1 : 0)
    }
}
