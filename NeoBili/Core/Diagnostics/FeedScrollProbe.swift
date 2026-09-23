#if PERFORMANCE_DEMO
import UIKit

/// Opt-in repeatable scrolling workload. Callback timing measures main-thread
/// delivery, not GPU presentation; pair the recording with Animation Hitches.
@MainActor
final class FeedScrollProbe: NSObject {
    static weak var attached: FeedScrollProbe?
    private var menuRecording = false
    private weak var view: UICollectionView?
    private var link: CADisplayLink?
    private var started: CFTimeInterval?
    private var previous: CFTimeInterval?
    private var direction: CGFloat = 1
    private var samples: [Sample] = []
    private var oldIdleTimer = false
    private var manual = ProcessInfo.processInfo.arguments.contains("--feed-scroll-manual")

    private struct Sample: Codable {
        let elapsed: Double
        let callbackInterval: Double
        let scheduledInterval: Double
        let offset: Double
        let contentHeight: Double
        let itemCount: Int
        let thermalState: Int
        let lowPowerMode: Bool
    }

    func attach(_ view: UICollectionView) {
        self.view = view
        Self.attached = self
        guard manual || ProcessInfo.processInfo.arguments.contains("--feed-scroll-probe") else { return }
        start()
    }

    func startManualRecording() {
        stop()
        manual = true
        menuRecording = true
        start()
    }

    private func start() {
        guard link == nil else { return }
        started = nil
        previous = nil
        direction = 1
        samples = []
        oldIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        samples.reserveCapacity(5_000)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Request the device's full rate only in this diagnostic workload.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let view, view.window != nil, UIApplication.shared.applicationState == .active else {
            previous = nil
            return
        }
        guard view.contentSize.height > view.bounds.height * 1.5 else { return }
        let now = CACurrentMediaTime()
        let moving = view.isDragging || view.isDecelerating
        if started == nil {
            guard !manual || moving else { return }
            started = now
        }
        let elapsed = now - (started ?? now)
        guard menuRecording || elapsed < (manual ? 30 : 35) else { stop(); return }
        if manual && !moving { previous = nil; return }
        defer { previous = now }
        // Automatic runs settle for five seconds; manual runs begin with the first drag.
        guard elapsed > (manual ? 0 : 5), let previous else { return }
        let interval = now - previous
        let minimum = -view.adjustedContentInset.top
        let maximum = max(minimum, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        let offset = manual ? view.contentOffset.y : min(maximum, max(minimum, view.contentOffset.y + direction * 900 * interval))
        if offset >= maximum { direction = -1 }
        if offset <= minimum { direction = 1 }
        let count = (0..<view.numberOfSections).reduce(0) { $0 + view.numberOfItems(inSection: $1) }
        samples.append(Sample(elapsed: elapsed, callbackInterval: interval,
                              scheduledInterval: link.targetTimestamp - link.timestamp,
                              offset: offset, contentHeight: view.contentSize.height, itemCount: count,
                              thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                              lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled))
        if !manual { view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: false) }
    }

    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        UIApplication.shared.isIdleTimerDisabled = oldIdleTimer
        guard !samples.isEmpty else { return }
        let result = samples
        let filename = manual ? "feed-scroll-manual.json" : "feed-scroll.json"
        samples = []
        Task.detached(priority: .utility) {
            do {
                let directory = URL.documentsDirectory.appending(path: "Performance")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(result).write(to: directory.appending(path: filename), options: .atomic)
            } catch { print("Feed scroll probe save failed: \(error)") }
        }
    }
}
#endif
