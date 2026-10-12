import SwiftUI
import UIKit

struct PlayerGestureDrag {
    let translation: CGSize
    let location: CGPoint
    let startLocation: CGPoint
}

/// Independent tap/hold/pan recognition. PiliPlus handles double taps on the
/// second down and uses 300 ms holds in its default configuration; our tap
/// disambiguation is explicitly bounded rather than delegated to UIKit timing.
struct PlayerGestureInput: UIViewRepresentable {
    let canLongPress: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onLongPressChanged: (Bool) -> Void
    let onDrag: (PlayerGestureDrag, Bool) -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> PlayerGestureInputView { PlayerGestureInputView() }

    func updateUIView(_ view: PlayerGestureInputView, context: Context) {
        view.onTap = onTap
        view.onDoubleTap = onDoubleTap
        view.onLongPressChanged = onLongPressChanged
        view.onDrag = onDrag
        view.onCancel = onCancel
        view.hold.isEnabled = canLongPress
    }

    static func dismantleUIView(_ view: PlayerGestureInputView, coordinator: ()) {
        view.cancelInteraction()
    }
}

final class PlayerGestureInputView: UIView, UIGestureRecognizerDelegate {
    let tap = PlayerTapGestureRecognizer()
    let hold = UILongPressGestureRecognizer()
    let pan = UIPanGestureRecognizer()
    var onTap: () -> Void = {}
    var onDoubleTap: () -> Void = {}
    var onLongPressChanged: (Bool) -> Void = { _ in }
    var onDrag: (PlayerGestureDrag, Bool) -> Void = { _, _ in }
    var onCancel: () -> Void = {}
    private var holding = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        hold.minimumPressDuration = 0.3
        hold.allowableMovement = 18
        pan.maximumNumberOfTouches = 1
        for recognizer in [tap, hold, pan] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        tap.onRecognized = { [weak self] isDouble in
            guard let self else { return }
            if isDouble { onDoubleTap() } else { onTap() }
        }
        hold.addTarget(self, action: #selector(held(_:)))
        pan.addTarget(self, action: #selector(panned(_:)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func held(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard !holding else { return }
            holding = true
            onLongPressChanged(true)
        case .ended, .cancelled, .failed:
            endHold()
        default: break
        }
    }

    @objc func panned(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed, .ended:
            let translation = recognizer.translation(in: self)
            let location = recognizer.location(in: self)
            onDrag(PlayerGestureDrag(translation: CGSize(width: translation.x, height: translation.y),
                                     location: location,
                                     startLocation: CGPoint(x: location.x - translation.x,
                                                            y: location.y - translation.y)),
                   recognizer.state == .ended)
        case .cancelled, .failed: onCancel()
        default: break
        }
    }

    func cancelInteraction() {
        tap.cancelPendingTap()
        endHold()
        onCancel()
    }

    private func endHold() {
        guard holding else { return }
        holding = false
        onLongPressChanged(false)
    }
}

/// A short, explicit tap window keeps controls responsive. Once a second down
/// qualifies, playback changes immediately, without waiting for its release.
final class PlayerTapGestureRecognizer: UIGestureRecognizer {
    static let doubleTapWindow: TimeInterval = 0.18
    static let movementTolerance: CGFloat = 18
    var onRecognized: (Bool) -> Void = { _ in }
    private var origin: CGPoint?
    private var downTime: TimeInterval = 0
    private var firstRelease: (point: CGPoint, time: TimeInterval)?
    private var deadline: Task<Void, Never>?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1, let touch = touches.first, origin == nil else {
            cancelPendingTap()
            state = .failed
            return
        }
        began(at: touch.location(in: view), time: touch.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { moved(to: touch.location(in: view)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { ended(at: touch.location(in: view), time: touch.timestamp) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        cancelPendingTap()
        state = .cancelled
    }

    override func reset() {
        super.reset()
        cancelPendingTap()
    }

    func began(at point: CGPoint, time: TimeInterval) {
        guard state == .possible else { return }
        if let firstRelease,
           time - firstRelease.time <= Self.doubleTapWindow,
           hypot(point.x - firstRelease.point.x, point.y - firstRelease.point.y) <= 44 {
            recognize(isDouble: true)
            return
        }
        cancelPendingTap()
        origin = point
        downTime = time
    }

    func moved(to point: CGPoint) {
        guard state == .possible, let origin else { return }
        if hypot(point.x - origin.x, point.y - origin.y) > Self.movementTolerance {
            cancelPendingTap()
            state = .failed
        }
    }

    func ended(at point: CGPoint, time: TimeInterval) {
        guard state == .possible, origin != nil else { return }
        moved(to: point)
        guard state == .possible else { return }
        guard time - downTime < 0.3 else {
            cancelPendingTap()
            state = .failed
            return
        }
        origin = nil
        firstRelease = (point, time)
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Self.doubleTapWindow)) }
            catch { return }
            self?.expire(at: time + Self.doubleTapWindow)
        }
    }

    func expire(at time: TimeInterval) {
        guard state == .possible, let firstRelease,
              time >= firstRelease.time + Self.doubleTapWindow else { return }
        recognize(isDouble: false)
    }

    func cancelPendingTap() {
        deadline?.cancel()
        deadline = nil
        origin = nil
        firstRelease = nil
    }

    private func recognize(isDouble: Bool) {
        cancelPendingTap()
        state = .recognized
        onRecognized(isDouble)
    }
}
