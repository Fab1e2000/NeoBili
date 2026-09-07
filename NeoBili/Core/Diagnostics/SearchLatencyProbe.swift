#if DEBUG
import SwiftUI
import UIKit
import QuartzCore
import os

/// Opt-in physical-device probe. Normal launches do not install observers or timers.
@MainActor
final class SearchLatencyProbe: NSObject {
    static let shared = SearchLatencyProbe()
    static let enabled = ProcessInfo.processInfo.arguments.contains("--search-latency-probe")
        || ProcessInfo.processInfo.arguments.contains("--search-appearance-probe")
        || ProcessInfo.processInfo.arguments.contains("--search-interaction-only")
    private let log = OSLog(subsystem: "com.elsterlee.NeoBili", category: "SearchLatency")
    private var started = false
    private var origin = CACurrentMediaTime()
    private var events: [[String: Any]] = []
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var bodyCounts: [String: Int] = [:]
    private var phase = "idle"

    static func body(_ name: String) {
        guard enabled else { return }
        shared.bodyCounts[name, default: 0] += 1
    }

    static func focusChanged(_ focused: Bool) {
        guard enabled else { return }
        shared.record("focus_changed", extra: ["focused": focused])
    }

    func run(focus: @MainActor (Bool) -> Void,
             query: () -> String, isSearching: () -> Bool, cancel: () -> Void) async {
        guard Self.enabled, !started else { return }
        started = true
        origin = CACurrentMediaTime()
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: name, object: nil)
        }
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
        record("probe_started", extra: ["os": UIDevice.current.systemVersion])
        defer {
            link.invalidate()
            displayLink = nil
            NotificationCenter.default.removeObserver(self)
            save()
        }
        do {
            if ProcessInfo.processInfo.arguments.contains("--search-interaction-only") {
                try await Task.sleep(for: .seconds(3))
                try await checkInteraction(focus: focus, query: query, isSearching: isSearching, cancel: cancel)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--search-appearance-probe") {
                try await Task.sleep(for: .seconds(3))
                focus(true)
                try await Task.sleep(for: .seconds(1))
                if let field = mountedSearchField() {
                    field.text = "音乐"
                    field.sendActions(for: .editingChanged)
                }
                try await Task.sleep(for: .seconds(2))
                record("appearance_ready")
                try await Task.sleep(for: .seconds(25))
                cancel()
                return
            }
            // Leave time to attach Instruments and let the recommendation feed settle.
            try await Task.sleep(for: .seconds(15))
            for attempt in 1...2 {
                phase = "focus_\(attempt)"
                record("request_focus", extra: ["attempt": attempt])
                focus(true)
                try await Task.sleep(for: .seconds(4))
                record("request_blur", extra: ["attempt": attempt])
                focus(false)
                try await Task.sleep(for: .seconds(2))
            }
            phase = "done"
            record("probe_finished")
            if ProcessInfo.processInfo.arguments.contains("--search-interaction-probe") {
                try await checkInteraction(focus: focus, query: query, isSearching: isSearching, cancel: cancel)
            }
        } catch {
            record("probe_cancelled")
        }
    }

    /// Exercise the actual mounted UIKit field and its delegate/bindings without an XCTest runner.
    /// This checks composition and application wiring, not synthesized physical touches.
    private func checkInteraction(focus: (Bool) -> Void, query: () -> String,
                                  isSearching: () -> Bool, cancel: () -> Void) async throws {
        phase = "interaction"
        let field = mountedSearchField()
        guard let field else { record("check_missing_field", extra: ["passed": false]); return }
        var ancestor: UIView? = field
        while ancestor != nil && !(ancestor is UISearchBar) { ancestor = ancestor?.superview }
        let searchBar = ancestor as? UISearchBar
        focus(true)
        try await Task.sleep(for: .seconds(1))
        record("check_focus", extra: ["passed": field.isFirstResponder])
        field.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
        field.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(300))
        record("check_marked_text", extra: ["passed": field.markedTextRange != nil && query() == "zhong"])
        field.setMarkedText("中", selectedRange: NSRange(location: 1, length: 0))
        field.unmarkText()
        field.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(300))
        record("check_composition_commit", extra: ["passed": query() == "中"])
        field.text = ""
        field.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(300))
        record("check_clear", extra: ["passed": query().isEmpty && !isSearching()])
        field.text = "music"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(300))
        if let searchBar {
            searchBar.delegate?.searchBarSearchButtonClicked?(searchBar)
        } else {
            _ = field.delegate?.textFieldShouldReturn?(field)
        }
        try await Task.sleep(for: .seconds(2))
        record("check_submit", extra: ["passed": isSearching() && !field.isFirstResponder && query() == "music"])
        focus(true)
        try await Task.sleep(for: .milliseconds(500))
        if let searchBar {
            searchBar.delegate?.searchBarCancelButtonClicked?(searchBar)
        } else {
            cancel()
        }
        try await Task.sleep(for: .milliseconds(500))
        record("check_cancel", extra: ["passed": !isSearching() && !field.isFirstResponder && query().isEmpty])
    }

    private func mountedSearchField() -> UISearchTextField? {
        func findField(_ view: UIView) -> UISearchTextField? {
            if let field = view as? UISearchTextField { return field }
            return view.subviews.lazy.compactMap { findField($0) }.first
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).lazy.compactMap { findField($0) }.first
    }

    @objc private func keyboard(_ notification: Notification) {
        record(notification.name.rawValue, extra: [
            "animationSeconds": notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
        ])
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if lastFrame > 0, now - lastFrame > 0.05 {
            record("frame_gap", extra: ["milliseconds": (now - lastFrame) * 1_000])
        }
        lastFrame = now
    }

    private func record(_ name: String, extra: [String: Any] = [:]) {
        let elapsed = (CACurrentMediaTime() - origin) * 1_000
        var event = extra
        event["event"] = name
        event["millisecondsSinceStart"] = elapsed
        event["phase"] = phase
        event["bodyCounts"] = bodyCounts
        events.append(event)
        os_signpost(.event, log: log, name: "SearchProbe", "%{public}@ phase=%{public}@ t=%.1fms", name, phase, elapsed)
        print("[SearchProbe] \(name) phase=\(phase) t=\(Int(elapsed))ms \(extra)")
    }

    private func save() {
        let url = URL.documentsDirectory.appending(path: "search-latency-probe.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            print("[SearchProbe] saved \(url.lastPathComponent)")
        } catch {
            print("[SearchProbe] save failed: \(error)")
        }
    }
}
#endif
