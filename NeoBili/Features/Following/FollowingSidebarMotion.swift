import SwiftUI
import UIKit

/// 页面、头像、玻璃边界读取同一份进度，避免 SwiftUI 与 Core Animation 各自缓动。
@MainActor @Observable
final class FollowingSidebarMotion {
    private(set) var progress: CGFloat = 0
    private(set) var isDragging = false
    @ObservationIgnored private var dragStart: CGFloat = 0
    @ObservationIgnored private var sample = FollowingSidebarPhysics.Sample(progress: 0, velocity: 0)
    @ObservationIgnored private var target: CGFloat = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastTime: CFTimeInterval = 0

    func drag(translation: CGFloat) {
        if !isDragging {
            stop()
            dragStart = progress
            isDragging = true
        }
        publish(FollowingSidebarPhysics.dragProgress(start: dragStart, translation: translation))
    }

    @discardableResult
    func endDrag(velocity: CGFloat?, reduceMotion: Bool) -> Bool {
        let destination = velocity.map { FollowingSidebarPhysics.target(progress: progress, velocity: $0) }
            ?? (dragStart >= 0.5 ? 1 : 0)
        isDragging = false
        settle(expanded: destination == 1, velocity: velocity ?? 0, reduceMotion: reduceMotion)
        return destination == 1
    }

    func settle(expanded: Bool, velocity: CGFloat = 0, reduceMotion: Bool) {
        guard !isDragging else { return }
        let destination: CGFloat = expanded ? 1 : 0
        if !reduceMotion, target == destination, displayLink != nil { return }
        stop()
        target = destination
        if reduceMotion || (progress == destination && velocity == 0) {
            publish(destination)
            return
        }
        sample = .init(progress: progress, velocity: velocity / FollowingSidebarPhysics.displacement)
        lastTime = CACurrentMediaTime()
        // CADisplayLink retains its target; a weak trampoline permits deallocation after navigation.
        let link = CADisplayLink(target: TickTarget(owner: self), selector: #selector(TickTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func reset() {
        stop()
        isDragging = false
        target = 0
        publish(0)
    }

    private func tick(_ link: CADisplayLink) {
        let timestamp = link.targetTimestamp
        let elapsed = max(0, timestamp - lastTime)
        lastTime = timestamp
        sample = FollowingSidebarPhysics.advance(sample, toward: target, elapsed: elapsed)
        if abs(sample.progress - target) < 0.0005 && abs(sample.velocity) < 0.005 {
            publish(target)
            stop()
        } else {
            publish(sample.progress)
        }
    }

    private func publish(_ value: CGFloat) {
        guard progress != value else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = value }
    }

    private func stop() { displayLink?.invalidate(); displayLink = nil }

    @MainActor private final class TickTarget: NSObject {
        weak var owner: FollowingSidebarMotion?
        init(owner: FollowingSidebarMotion) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.tick(link)
        }
    }
}

/// 进度观察仅发生在这个修饰器内，不让每个显示帧重新求值整份动态数据和卡片。
struct FollowingFeedPresentation: ViewModifier {
    let motion: FollowingSidebarMotion
    let side: FollowingSidebarSide

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let layout = FollowingFeedGeometry(width: geometry.size.width, height: geometry.size.height,
                                               progress: motion.progress)
            content
                .frame(width: geometry.size.width, height: layout.unscaledHeight)
                .scaleEffect(layout.scale, anchor: side == .left ? .topLeading : .topTrailing)
                .offset(x: layout.displacement * (side == .left ? 1 : -1))
        }
    }
}
