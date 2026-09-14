import Foundation
import CoreGraphics

/// Upper actions and lower timeline each occupy one row, independent of aspect ratio.
struct PlayerChromeLayout {
    enum Mode { case expanded, inline, compact, minimal }
    let mode: Mode
    let back: CGRect
    let more: CGRect
    let transport: CGRect
    let timeline: CGRect
    let fullScreen: CGRect
    let danmaku: CGRect
    let metadata: CGRect
    let secondaryActions: CGRect
    let videoQuality: CGRect
    let audioQuality: CGRect

    init(bounds: CGRect, textScale: CGFloat = 1, isFullScreen: Bool = false,
         hasVideoQuality: Bool = false, hasAudioQuality: Bool = false,
         hasDanmaku: Bool = false,
         videoQualityWidth: CGFloat? = nil, audioQualityWidth: CGFloat? = nil) {
        let target: CGFloat = 48
        let gap: CGFloat = 6
        let scale = textScale.isFinite ? min(max(textScale, 1), 1.5) : 1
        mode = bounds.height >= 320 * scale ? .expanded : bounds.height >= 152 ? .inline : bounds.height >= 96 ? .compact : .minimal
        let lowerY = max(bounds.minY, bounds.maxY - target)
        fullScreen = CGRect(x: bounds.maxX - target, y: lowerY, width: target, height: target)
        timeline = CGRect(x: bounds.minX, y: lowerY,
                          width: max(0, fullScreen.minX - gap - bounds.minX), height: target)
        secondaryActions = .zero
        // The collapsed title strip cannot fit two 48pt hit rows. Its own page
        // controls handle expansion; keep only the timeline/fullscreen row here.
        guard mode != .minimal else {
            back = .zero; more = .zero; transport = .zero; danmaku = .zero
            videoQuality = .zero; audioQuality = .zero; metadata = .zero
            return
        }
        back = CGRect(x: bounds.minX, y: bounds.minY, width: target, height: target)
        more = CGRect(x: bounds.maxX - target, y: bounds.minY, width: target, height: target)
        danmaku = hasDanmaku ? CGRect(x: more.minX - gap - target, y: bounds.minY, width: target, height: target) : .zero
        let rightEdge = hasDanmaku ? danmaku.minX : more.minX
        let count = (hasVideoQuality ? 1 : 0) + (hasAudioQuality ? 1 : 0)
        let available = max(0, rightEdge - back.maxX - gap * CGFloat(count + 1))
        if count > 0, available >= CGFloat(count) * target {
            let requestedVideo = hasVideoQuality ? max(target, videoQualityWidth ?? 112 * scale) : 0
            let requestedAudio = hasAudioQuality ? max(target, audioQualityWidth ?? 112 * scale) : 0
            let extra = max(0, requestedVideo + requestedAudio - target * CGFloat(count))
            let compression = extra > 0 ? min(1, max(0, available - target * CGFloat(count)) / extra) : 1
            let videoWidth = hasVideoQuality ? target + (requestedVideo - target) * compression : 0
            let audioWidth = hasAudioQuality ? target + (requestedAudio - target) * compression : 0
            let start = rightEdge - gap - videoWidth - audioWidth - CGFloat(count - 1) * gap
            videoQuality = hasVideoQuality ? CGRect(x: start, y: bounds.minY, width: videoWidth, height: target) : .zero
            audioQuality = hasAudioQuality ? CGRect(x: hasVideoQuality ? start + videoWidth + gap : start,
                                                     y: bounds.minY, width: audioWidth, height: target) : .zero
            let width = min(240, start - back.maxX - gap * 2)
            metadata = width >= 120 ? CGRect(x: back.maxX + gap, y: bounds.minY, width: width, height: target) : .zero
        } else {
            videoQuality = .zero; audioQuality = .zero
            let width = min(240, rightEdge - back.maxX - gap * 2)
            metadata = width >= 120 ? CGRect(x: back.maxX + gap, y: bounds.minY, width: width, height: target) : .zero
        }
        let space = max(0, bounds.height - target * 2)
        let diameter: CGFloat = min(mode == .expanded ? 72 : 56, space)
        transport = diameter >= target
            ? CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
            : .zero
    }

    var showsTimeLabels: Bool { timeline.width >= 200 }
}
