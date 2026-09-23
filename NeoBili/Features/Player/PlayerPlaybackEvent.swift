import Foundation

enum PlayerPlaybackEvent: Sendable {
    case firstFrame
    case playing(Bool)
    case buffering(Bool)
    case position(TimeInterval)
    case seekCompleted(TimeInterval)
    case duration(TimeInterval)
    case displayAspectRatio(Double)
    case decodedVideoSize(width: Int, height: Int)
    case buffered(TimeInterval)
    case ended
    case error(String)
}

enum PlayerSessionError: LocalizedError {
    case invalidSource
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource: return "视频地址无效"
        case .playbackFailed(let detail): return "视频加载失败：\(detail)"
        }
    }
}
