import Foundation

enum PlaybackQuality {
    static let videoStorageKey = "neobili.preferredQuality"
    static let audioStorageKey = "neobili.preferredAudioQuality"
    // 1080P 60帧、Hi-Res 无损；账号或视频没有这一档时自动降到可用的最高档。
    static let defaultVideoQuality = 116
    static let defaultAudioQuality = 30251
    static let videoOptions: [(id: Int, title: String)] = [
        (16, "360P"), (32, "480P"), (64, "720P"), (74, String(localized: "720P 60帧")),
        (80, "1080P"), (112, String(localized: "1080P 高码率")), (116, String(localized: "1080P 60帧")),
        (120, "4K"), (127, "8K")
    ]
    // 对照 PiliPlus AudioQuality；Hi-Res / 杜比使用独立的扩展音轨。
    static let audioOptions: [(id: Int, title: String)] = [
        (0, String(localized: "自动（最佳可用）")), (30216, "64K"), (30232, "132K"),
        (30280, "192K"), (30250, String(localized: "杜比全景声")), (30251, String(localized: "Hi-Res 无损"))
    ]
    static func videoTitle(_ id: Int) -> String {
        videoOptions.first { $0.id == id }?.title ?? [125: "HDR", 126: String(localized: "杜比视界")][id] ?? String(localized: "画质 \(id)")
    }
    static func audioTitle(_ id: Int) -> String {
        if id == 30255 { return String(localized: "杜比全景声") }
        return audioOptions.first { $0.id == id }?.title ?? String(localized: "音轨 \(id)")
    }
    static func audioRank(_ id: Int) -> Int {
        switch id {
        case 30251: 5
        case 30250, 30255: 4
        case 30280: 3
        case 30232: 2
        case 30216: 1
        default: 0
        }
    }
}
