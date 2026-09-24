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
    /// 全屏时进度条与全屏按钮之间的「发弹幕」按钮。
    let sendDanmaku: CGRect
    let danmaku: CGRect
    let metadata: CGRect
    let secondaryActions: CGRect
    let videoQuality: CGRect
    let audioQuality: CGRect

    init(bounds: CGRect, textScale: CGFloat = 1, isFullScreen: Bool = false,
         hasVideoQuality: Bool = false, hasAudioQuality: Bool = false,
         hasDanmaku: Bool = false, hasSendDanmaku: Bool = false,
         videoQualityWidth: CGFloat? = nil, audioQualityWidth: CGFloat? = nil,
         spacing: CGFloat = 16) {
        let target: CGFloat = 48
        // 圆形按钮在 48pt 点击区里只画 32pt，左右各空 8pt；画质胶囊、标题和进度条撑满自己的区域。
        // 间距按「看得见的部分」算，任意两个相邻控件之间都是 `spacing`（全屏时可在设置里调）。
        let circleInset: CGFloat = 8
        let spacing = max(0, spacing)
        let circleToCircle = spacing - circleInset * 2
        let circleToPill = spacing - circleInset
        let pillToPill = spacing
        let scale = textScale.isFinite ? min(max(textScale, 1), 1.5) : 1
        mode = bounds.height >= 320 * scale ? .expanded : bounds.height >= 152 ? .inline : bounds.height >= 96 ? .compact : .minimal
        let lowerY = max(bounds.minY, bounds.maxY - target)
        fullScreen = CGRect(x: bounds.maxX - target, y: lowerY, width: target, height: target)
        // 全屏时进度条缩短，把右侧让给「发弹幕」。
        sendDanmaku = isFullScreen && hasSendDanmaku
            ? CGRect(x: fullScreen.minX - circleToCircle - target, y: lowerY, width: target, height: target) : .zero
        let timelineEnd = (sendDanmaku.isEmpty ? fullScreen.minX : sendDanmaku.minX) - circleToPill
        // 左端与上方返回按钮的圆形对齐。
        let timelineStart = bounds.minX + circleInset
        timeline = CGRect(x: timelineStart, y: lowerY, width: max(0, timelineEnd - timelineStart), height: target)
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
        danmaku = hasDanmaku ? CGRect(x: more.minX - circleToCircle - target, y: bounds.minY, width: target, height: target) : .zero
        let rightEdge = hasDanmaku ? danmaku.minX : more.minX
        let count = (hasVideoQuality ? 1 : 0) + (hasAudioQuality ? 1 : 0)
        let available = max(0, rightEdge - back.maxX - circleToPill * 2 - pillToPill * CGFloat(max(0, count - 1)))
        if count > 0, available >= CGFloat(count) * target {
            let requestedVideo = hasVideoQuality ? max(target, videoQualityWidth ?? 112 * scale) : 0
            let requestedAudio = hasAudioQuality ? max(target, audioQualityWidth ?? 112 * scale) : 0
            let extra = max(0, requestedVideo + requestedAudio - target * CGFloat(count))
            let compression = extra > 0 ? min(1, max(0, available - target * CGFloat(count)) / extra) : 1
            let videoWidth = hasVideoQuality ? target + (requestedVideo - target) * compression : 0
            let audioWidth = hasAudioQuality ? target + (requestedAudio - target) * compression : 0
            let start = rightEdge - circleToPill - videoWidth - audioWidth - CGFloat(count - 1) * pillToPill
            videoQuality = hasVideoQuality ? CGRect(x: start, y: bounds.minY, width: videoWidth, height: target) : .zero
            audioQuality = hasAudioQuality ? CGRect(x: hasVideoQuality ? start + videoWidth + pillToPill : start,
                                                     y: bounds.minY, width: audioWidth, height: target) : .zero
            let width = min(240, start - pillToPill - back.maxX - circleToPill)
            metadata = width >= 120 ? CGRect(x: back.maxX + circleToPill, y: bounds.minY, width: width, height: target) : .zero
        } else {
            videoQuality = .zero; audioQuality = .zero
            let width = min(240, rightEdge - back.maxX - circleToPill * 2)
            metadata = width >= 120 ? CGRect(x: back.maxX + circleToPill, y: bounds.minY, width: width, height: target) : .zero
        }
        let space = max(0, bounds.height - target * 2)
        let diameter: CGFloat = min(mode == .expanded ? 72 : 56, space)
        transport = diameter >= target
            ? CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
            : .zero
    }

    var showsTimeLabels: Bool { timeline.width >= 200 }
}
