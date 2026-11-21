import Foundation

public struct CastDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let manufacturer: String?
    public let modelName: String?
    public let location: URL
    public let avTransportControlURL: URL
    public let renderingControlURL: URL?

    public init(
        id: String,
        name: String,
        manufacturer: String? = nil,
        modelName: String? = nil,
        location: URL,
        avTransportControlURL: URL,
        renderingControlURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.location = location
        self.avTransportControlURL = avTransportControlURL
        self.renderingControlURL = renderingControlURL
    }

    public var subtitle: String {
        let parts = [manufacturer, modelName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return location.host ?? location.absoluteString
    }
}

public enum CastMediaKind: String, Hashable, Sendable {
    case video
    case live
    case offlineVideo

    public var supportsSeeking: Bool {
        switch self {
        case .video, .offlineVideo: true
        case .live: false
        }
    }
}

public enum CastMediaSource: Hashable, Sendable {
    case remoteHTTP(url: URL, headers: [String: String], mimeType: String)
    case remoteDualTrack(videoURL: URL, audioURL: URL?, headers: [String: String])
    case localFile(url: URL, mimeType: String)
    case localDualTrack(videoURL: URL, audioURL: URL)

    /// 实时混流输出使用时间偏移重定位，不依赖电视端字节 Range Seek。
    public var usesServerSideTimeSeek: Bool {
        if case .remoteDualTrack = self { return true }
        return false
    }
}

public struct CastMediaRequest: Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: CastMediaKind
    public let startPosition: TimeInterval
    public let duration: TimeInterval
    public let source: CastMediaSource

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        kind: CastMediaKind,
        startPosition: TimeInterval = 0,
        duration: TimeInterval = 0,
        source: CastMediaSource
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.startPosition = max(0, startPosition)
        self.duration = max(0, duration)
        self.source = source
    }

    public func withStartPosition(_ seconds: TimeInterval) -> CastMediaRequest {
        CastMediaRequest(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            startPosition: seconds,
            duration: duration,
            source: source
        )
    }
}

public enum CastTransportState: String, Hashable, Sendable {
    case playing
    case paused
    case transitioning
    case stopped
    case unknown

    public var isPlaying: Bool { self == .playing }
}

public struct CastPlaybackPosition: Hashable, Sendable {
    public let position: TimeInterval
    public let duration: TimeInterval

    public init(position: TimeInterval, duration: TimeInterval) {
        self.position = max(0, position)
        self.duration = max(0, duration)
    }
}

public enum CastError: LocalizedError, Sendable {
    case localNetworkUnavailable
    case invalidDeviceAddress
    case unsupportedDevice
    case mediaUnavailable(String)
    case offlineMuxFailed(String)
    case proxyStartFailed(String)
    case soapFault(code: String?, message: String)
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .localNetworkUnavailable:
            String(localized: "未检测到局域网连接，请确认手机与投屏设备在同一 Wi-Fi 下")
        case .invalidDeviceAddress:
            String(localized: "设备地址无效，请输入正确的 http:// 设备描述地址")
        case .unsupportedDevice:
            String(localized: "该设备不支持 DLNA 投屏控制（缺少 AVTransport 服务）")
        case .mediaUnavailable(let reason):
            reason
        case .offlineMuxFailed(let reason):
            String(localized: "离线视频封装失败：\(reason)")
        case .proxyStartFailed(let reason):
            String(localized: "本地投屏服务启动失败：\(reason)")
        case .soapFault(let code, let message):
            if let code, !code.isEmpty {
                String(localized: "投屏设备返回错误（\(code)）：\(message)")
            } else {
                String(localized: "投屏设备返回错误：\(message)")
            }
        case .transportFailed(let message):
            message
        }
    }
}
