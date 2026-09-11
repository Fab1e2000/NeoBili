import Foundation
import CoreGraphics

/// 保持返回、播放和全屏的空间关系；高度不足时先省略信息，再缩短进度条。
struct PlayerChromeLayout {
    enum Mode { case expanded, inline, compact, minimal }
    let mode: Mode
    let back: CGRect
    let more: CGRect
    let transport: CGRect
    let timeline: CGRect
    let fullScreen: CGRect
    let metadata: CGRect
    let secondaryActions: CGRect
    let videoQuality: CGRect
    let audioQuality: CGRect

    init(bounds: CGRect, textScale: CGFloat = 1, isFullScreen: Bool = false,
         hasVideoQuality: Bool = false, hasAudioQuality: Bool = false,
         videoQualityWidth: CGFloat? = nil, audioQualityWidth: CGFloat? = nil) {
        let scale = textScale.isFinite ? min(max(textScale, 1), 1.5) : 1
        let target: CGFloat = 48
        let lowerY = max(bounds.minY, bounds.maxY - target)
        if bounds.height >= 320 * scale {
            mode = .expanded
            back = CGRect(x: bounds.minX, y: bounds.minY, width: target, height: target)
            more = CGRect(x: bounds.maxX - target, y: bounds.minY, width: target, height: target)
            transport = CGRect(x: bounds.midX - 46, y: bounds.midY - 46, width: 92, height: 92)
            // 全屏底部与标准非全屏一致：时间/进度和退出全屏只占一行。
            timeline = CGRect(x: bounds.minX, y: isFullScreen ? lowerY : lowerY - 60,
                              width: isFullScreen ? bounds.width - 56 : bounds.width, height: target)
            fullScreen = CGRect(x: bounds.maxX - target, y: lowerY, width: target, height: target)
            secondaryActions = isFullScreen ? .zero : CGRect(x: bounds.minX, y: lowerY,
                                      width: max(0, bounds.width - 56), height: target)
        } else if bounds.height >= 152 {
            mode = .inline
            back = CGRect(x: bounds.minX, y: bounds.minY, width: target, height: target)
            more = CGRect(x: bounds.maxX - target, y: bounds.minY, width: target, height: target)
            let diameter: CGFloat = bounds.height >= 176 ? 64 : target
            transport = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                               width: diameter, height: diameter)
            timeline = CGRect(x: bounds.minX, y: lowerY,
                              width: max(0, bounds.width - 56), height: target)
            fullScreen = CGRect(x: bounds.maxX - target, y: lowerY, width: target, height: target)
            secondaryActions = .zero
        } else if bounds.height >= 96 {
            mode = .compact
            back = CGRect(x: bounds.minX, y: bounds.minY, width: target, height: target)
            more = CGRect(x: bounds.maxX - target, y: bounds.minY, width: target, height: target)
            transport = CGRect(x: bounds.midX - 24, y: bounds.midY - 24, width: target, height: target)
            // 进度条只占左下方，中央播放按钮始终留在画面中心。
            timeline = CGRect(x: bounds.minX, y: lowerY,
                              width: max(0, transport.minX - bounds.minX - 12), height: target)
            fullScreen = CGRect(x: bounds.maxX - target, y: lowerY, width: target, height: target)
            secondaryActions = .zero
        } else {
            mode = .minimal
            let centerY = max(bounds.minY, bounds.midY - 24)
            back = CGRect(x: bounds.minX, y: centerY, width: target, height: target)
            more = CGRect(x: bounds.maxX - 104, y: centerY, width: target, height: target)
            transport = CGRect(x: bounds.midX - 24, y: centerY, width: target, height: target)
            timeline = CGRect(x: back.maxX + 8, y: centerY,
                              width: max(0, transport.minX - back.maxX - 16), height: target)
            fullScreen = CGRect(x: bounds.maxX - target, y: centerY, width: target, height: target)
            secondaryActions = .zero
        }

        let count = (hasVideoQuality ? 1 : 0) + (hasAudioQuality ? 1 : 0)
        if count > 0, mode == .expanded || mode == .inline {
            let available = max(0, more.minX - back.maxX - 16 - CGFloat(count - 1) * 8)
            let requestedVideo = hasVideoQuality ? max(target, videoQualityWidth ?? 112 * scale) : 0
            let requestedAudio = hasAudioQuality ? max(target, audioQualityWidth ?? 112 * scale) : 0
            // 宽度由实际文字决定；空间不足时只压缩文字两侧的富余，保留48pt点击目标。
            let extra = max(0, requestedVideo + requestedAudio - target * CGFloat(count))
            let compression = extra > 0 ? min(1, max(0, available - target * CGFloat(count)) / extra) : 1
            let videoWidth = hasVideoQuality ? target + (requestedVideo - target) * compression : 0
            let audioWidth = hasAudioQuality ? target + (requestedAudio - target) * compression : 0
            let start = more.minX - 8 - (videoWidth + audioWidth + CGFloat(count - 1) * 8)
            videoQuality = hasVideoQuality ? CGRect(x: start, y: bounds.minY, width: videoWidth, height: target) : .zero
            audioQuality = hasAudioQuality ? CGRect(x: hasVideoQuality ? start + videoWidth + 8 : start,
                                                    y: bounds.minY, width: audioWidth, height: target) : .zero
            let metadataWidth = min(240, start - back.maxX - 16)
            metadata = mode == .expanded && metadataWidth >= 120
                ? CGRect(x: back.maxX + 8, y: bounds.minY, width: metadataWidth, height: target) : .zero
        } else {
            videoQuality = .zero
            audioQuality = .zero
            let width = min(240, max(0, bounds.width - 112))
            metadata = mode == .expanded ? CGRect(x: bounds.midX - width / 2, y: bounds.minY,
                                                  width: width, height: target) : .zero
        }
    }

    var showsTimeLabels: Bool { mode == .expanded || mode == .inline }
}
