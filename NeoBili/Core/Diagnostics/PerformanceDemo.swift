#if PERFORMANCE_DEMO
import SwiftUI
import UIKit
import Darwin
import os

struct PerformanceSample: Codable {
    let timestamp: Date
    let elapsed: Double
    let stage: String
    let stageElapsed: Double
    let cpuPercentOneCore: Double?
    let footprintMiB: Double?
    let residentMiB: Double?
    let compressedMiB: Double?
    let thermal: Int
    let batteryLevel: Float?
    let batteryState: Int
    let lowPowerMode: Bool
    let appState: Int
    let landscape: Bool
    let playing: Bool
    let ready: Bool
    let videoOutputRequested: Bool?
}

struct PerformanceRecording: Codable {
    let schemaVersion = 1
    let started: Date
    let finished: Date?
    let os: String
    let build: String
    let processorCount: Int
    let sampleIntervalSeconds = 1
    let cpuDefinition = "100% = one CPU core; may exceed 100%"
    let powerDefinition = "Battery fraction and thermal state are context, not watts. Use the matching Instruments Power Profiler trace for power analysis."
    let notes: [String]
    let samples: [PerformanceSample]
}

@MainActor @Observable
final class PerformanceDemo {
    static let shared = PerformanceDemo()
    private(set) var stage = "未开始"
    private(set) var recording = false
    private(set) var automatic = false
    private(set) var latest: PerformanceSample?
    private(set) var fileURL: URL?
    private(set) var error: String?
    @ObservationIgnored private var samples: [PerformanceSample] = []
    @ObservationIgnored private var notes: [String] = []
    @ObservationIgnored private var sampler: Task<Void, Never>?
    @ObservationIgnored private var scenario: Task<Void, Never>?
    @ObservationIgnored private var started = Date()
    @ObservationIgnored private var origin = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var stageOrigin = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var previousCPU: Double?
    @ObservationIgnored private var previousTime: Double?
    @ObservationIgnored private var store: NowPlayingStore?
    @ObservationIgnored private var attached = false
    @ObservationIgnored private var oldBatteryMonitoring = false
    @ObservationIgnored private var oldIdleTimer = false
    private let log = OSLog(subsystem: "com.elsterlee.NeoBili.performance", category: .pointsOfInterest)

    func attach(_ store: NowPlayingStore) {
        guard !attached else { return }
        attached = true
        self.store = store
        let previous = URL.documentsDirectory.appending(path: "Performance/latest.json")
        if FileManager.default.fileExists(atPath: previous.path) { fileURL = previous }
        if ProcessInfo.processInfo.arguments.contains("--performance-auto") {
            runAutomatic()
        }
    }

    func start() {
        guard !recording else { return }
        samples = []; notes = []; error = nil
        started = Date(); origin = ProcessInfo.processInfo.systemUptime
        previousCPU = nil; previousTime = nil
        oldBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        oldIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        let directory = URL.documentsDirectory.appending(path: "Performance")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "run-\(Int(started.timeIntervalSince1970)).json")
        recording = true
        mark("手动采集")
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    func mark(_ value: String) {
        stage = value; stageOrigin = ProcessInfo.processInfo.systemUptime
        os_signpost(.event, log: log, name: "Performance stage", "%{public}s", value)
        print("PERFORMANCE_STAGE \(value)")
    }

    func stop() {
        let wasAutomatic = automatic
        scenario?.cancel(); scenario = nil
        automatic = false
        if let store { store.activeSession?.viewController.setVideoPresentation(store.activeSession?.surfacePresentation ?? .page) }
        guard recording else { return }
        if wasAutomatic { OrientationController.enterPortrait() }
        UIApplication.shared.isIdleTimerDisabled = oldIdleTimer
        sample()
        recording = false
        sampler?.cancel(); sampler = nil
        persist(finished: Date())
        UIDevice.current.isBatteryMonitoringEnabled = oldBatteryMonitoring
    }

    private func sample() {
        let uptime = ProcessInfo.processInfo.systemUptime
        var usage = rusage()
        let cpuTime: Double? = getrusage(RUSAGE_SELF, &usage) == 0
            ? Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 : nil
        var percent: Double?
        if let cpuTime, let previousCPU, let previousTime, uptime - previousTime >= 0.25 {
            percent = max(0, (cpuTime - previousCPU) / (uptime - previousTime) * 100)
        }
        previousCPU = cpuTime; previousTime = uptime
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let battery = UIDevice.current.batteryLevel
        let row = PerformanceSample(timestamp: Date(), elapsed: uptime - origin, stage: stage,
            stageElapsed: uptime - stageOrigin, cpuPercentOneCore: percent,
            footprintMiB: result == KERN_SUCCESS ? Double(vm.phys_footprint) / 1_048_576 : nil,
            residentMiB: result == KERN_SUCCESS ? Double(vm.resident_size) / 1_048_576 : nil,
            compressedMiB: result == KERN_SUCCESS ? Double(vm.compressed) / 1_048_576 : nil,
            thermal: ProcessInfo.processInfo.thermalState.rawValue,
            batteryLevel: battery >= 0 ? battery : nil, batteryState: UIDevice.current.batteryState.rawValue,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            appState: UIApplication.shared.applicationState.rawValue,
            landscape: scene?.effectiveGeometry.interfaceOrientation.isLandscape ?? false,
            playing: store?.isPlaying ?? false, ready: store?.hasRenderedFirstFrame ?? false,
            videoOutputRequested: store?.activeSession?.viewController.videoOutput.isEnabled)
        samples.append(row); latest = row
        if samples.count.isMultiple(of: 10) { persist(finished: nil) }
    }

    private func persist(finished: Date?) {
        guard let fileURL else { return }
        let record = PerformanceRecording(started: started, finished: finished,
            os: UIDevice.current.systemVersion,
            build: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") Release performance demo",
            processorCount: ProcessInfo.processInfo.processorCount, notes: notes, samples: samples)
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: fileURL, options: .atomic)
            // A stable path makes retrieval possible without guessing timestamps.
            try encoder.encode(record).write(to: fileURL.deletingLastPathComponent().appending(path: "latest.json"), options: .atomic)
        } catch { self.error = error.localizedDescription }
    }

    func runAutomatic() {
        stop(); start(); automatic = true
        oldIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        scenario = Task { [weak self] in
            guard let self, let store = self.store else { return }
            do {
                store.close()
                try await self.hold("首页静置", seconds: 35)
                self.mark("获取测试视频")
                let arguments = ProcessInfo.processInfo.arguments
                let route: VideoDetailRoute
                if let index = arguments.firstIndex(of: "--performance-bvid"),
                   arguments.indices.contains(index + 1) {
                    route = VideoDetailRoute(bvid: arguments[index + 1])
                } else {
                    let feed = HomeViewModel()
                    await feed.loadInitial()
                    guard let video = feed.videos.first(where: { $0.duration >= 240 && ($0.dimension?.width ?? 16) > ($0.dimension?.height ?? 9) }) ?? feed.videos.first else {
                        throw DemoError.failed(feed.errorMessage ?? "未获取到测试视频")
                    }
                    route = VideoDetailRoute(bvid: video.bvid, cid: video.cid, cover: video.pic, title: video.title)
                }
                self.notes.append("Test video: \(route.bvid). Same stream across video-output A/B stages; excludes account credentials and playback URLs.")
                store.open(route, from: "performance-entry")
                for _ in 0..<60 {
                    if store.hasRenderedFirstFrame { break }
                    try await Task.sleep(for: .seconds(1))
                }
                guard store.hasRenderedFirstFrame else { throw DemoError.failed("视频未能开始播放，本轮无有效播放对照") }
                if arguments.contains("--performance-bvid") {
                    await store.player?.seek(to: 0)
                    try await Task.sleep(for: .seconds(2))
                }
                try await self.hold("内联播放", seconds: 40)
                OrientationController.enterLandscape()
                try await self.hold("横屏全屏", seconds: 40)
                OrientationController.enterPortrait()
                try await Task.sleep(for: .seconds(2))
                store.dismissVideoPage()
                try await Task.sleep(for: .seconds(2))
                guard store.isMiniPlayerPresented else { throw DemoError.failed("缩略播放器未出现") }
                try await self.hold("缩略音频 A", seconds: 40)
                // Diagnostic-only control reproduces the previous invisible video workload.
                store.activeSession?.viewController.setVideoPresentation(.page)
                try await self.hold("缩略视频开启 对照", seconds: 40)
                store.activeSession?.viewController.setVideoPresentation(.mini)
                try await self.hold("缩略音频 B", seconds: 40)
                store.expandMiniPlayer()
                try await self.hold("重新展开", seconds: 20)
                store.close()
                try await self.hold("关闭后静置", seconds: 50)
                self.mark("完成")
                self.stop()
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    self.notes.append("Interrupted: \(error.localizedDescription)")
                }
                self.stop()
            }
        }
    }

    private func hold(_ stage: String, seconds: Int) async throws {
        try Task.checkCancellation()
        mark(stage)
        for _ in 0..<seconds {
            try await Task.sleep(for: .seconds(1))
            guard UIApplication.shared.applicationState == .active else { throw DemoError.failed("应用离开前台，自动对照已停止；请保持前台重试") }
            if ProcessInfo.processInfo.thermalState == .critical { throw DemoError.failed("系统热状态达到 critical，自动测试停止") }
        }
    }
    private enum DemoError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let message) = self { return message }; return nil }
    }
}

struct PerformanceDemoControl: View {
    let store: NowPlayingStore
    @Environment(\.videoTransitionNamespace) private var transition
    @State private var showing = false
    private var demo: PerformanceDemo { .shared }
    var body: some View {
        Button { showing = true } label: {
            Label(demo.recording ? "采集中" : "性能 Demo", systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
        }
        .padding(.trailing, 12)
        .videoTransitionSource("performance-entry", in: transition)
        .task { demo.attach(store) }
        .sheet(isPresented: $showing) {
            NavigationStack {
                List {
                    Section("真机性能采集 · Release") {
                        Text(demo.stage)
                        if let sample = demo.latest {
                            LabeledContent("CPU（单核 100%）", value: sample.cpuPercentOneCore.map { String(format: "%.1f%%", $0) } ?? "—")
                            LabeledContent("内存 footprint", value: sample.footprintMiB.map { String(format: "%.1f MiB", $0) } ?? "—")
                            LabeledContent("热状态", value: ["正常", "轻度", "严重", "临界"][min(sample.thermal, 3)])
                        }
                        Text("每秒采样。电量与热状态不等于功耗；功耗请结合 Instruments Power Profiler。不会记录账号凭据或视频地址。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("自动对照（约 5–6 分钟）") { showing = false; demo.runAutomatic() }.disabled(demo.recording)
                        Button("开始手动采集") { showing = false; demo.start() }.disabled(demo.recording)
                        Button("停止并保存") { demo.stop() }.disabled(!demo.recording)
                        if let url = demo.fileURL { ShareLink("导出 JSON", item: url) }
                    }
                    if let error = demo.error { Section("本轮说明") { Text(error) } }
                }
                .navigationTitle("性能采集")
                .toolbar { Button("完成") { showing = false } }
            }
        }
    }
}
#endif
