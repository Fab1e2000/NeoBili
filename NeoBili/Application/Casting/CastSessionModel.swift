import NeoBiliDomain
import Foundation
import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var castSession: CastSessionModel? = nil
}

@MainActor
@Observable
final class CastSessionModel {
    enum Phase: Equatable {
        case idle
        case connecting
        case casting
        case error(String)
    }

    private let service: CastService
    private let pollInterval: Duration
    private let recentDefaults: UserDefaults?
    private static let recentDevicesKey = "neobili.cast.recent-devices"
    private static let maxRecentDevices = 5

    private(set) var devices: [CastDevice] = []
    private(set) var recentDevices: [CastDevice] = []
    private(set) var isDiscovering = false
    private(set) var discoveryError: String?

    private(set) var activeDevice: CastDevice?
    private(set) var activeMedia: CastMediaRequest?
    private(set) var phase: Phase = .idle
    private(set) var transportState: CastTransportState = .unknown
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var volume: Int?
    private(set) var controlError: String?
    private(set) var isSwitchingStream = false

    var isScrubbing = false
    @ObservationIgnored var onPlaybackEnded: (@MainActor (String) -> Void)?
    private var baseTimeOffset: TimeInterval = 0
    private var discoverTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var sessionToken = UUID()
    private var endedNotifiedToken: UUID?

    init(service: CastService = CastService(),
         pollInterval: Duration = .seconds(1),
         recentDefaults: UserDefaults? = .standard) {
        self.service = service
        self.pollInterval = pollInterval
        self.recentDefaults = recentDefaults
        self.recentDevices = Self.loadRecentDevices(from: recentDefaults)
    }

    func removeRecentDevice(_ device: CastDevice) {
        recentDevices.removeAll { $0.id == device.id }
        saveRecentDevices()
    }

    var isActive: Bool {
        activeDevice != nil && activeMedia != nil && phase != .idle
    }

    /// 投屏模式是否开启：开启后离开播放页不会断开连接，点播新视频、离线缓存或直播时自动切换到当前投屏设备。
    var isCastModeActive: Bool {
        activeDevice != nil && phase != .idle
    }

    func isCasting(mediaID: String) -> Bool {
        activeMedia?.id == mediaID && phase != .idle
    }

    func discover(timeout: TimeInterval = 3.0) {
        discoverTask?.cancel()
        isDiscovering = true
        discoveryError = nil
        discoverTask = Task { [weak self, service] in
            defer { self?.isDiscovering = false }
            do {
                let found = try await service.discoverDevices(timeout: timeout)
                guard !Task.isCancelled, let self else { return }
                // 保留之前手动添加的设备，并与最新发现结果去重合并。
                var merged = found
                var seen = Set(found.map(\.id))
                for existing in self.devices where seen.insert(existing.id).inserted {
                    if existing.id == self.activeDevice?.id {
                        merged.insert(existing, at: 0)
                    }
                }
                self.devices = merged
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.discoveryError = error.localizedDescription
            }
        }
    }

    func addManualDevice(address: String) async throws -> CastDevice {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            throw CastError.invalidDeviceAddress
        }
        let device = try await service.inspectDevice(location: url)
        if !devices.contains(where: { $0.id == device.id }) {
            devices.insert(device, at: 0)
        }
        rememberRecentDevice(device)
        discoveryError = nil
        return device
    }

    @discardableResult
    func startCasting(device: CastDevice, media: CastMediaRequest) async -> Bool {
        pollTask?.cancel()
        let token = UUID()
        sessionToken = token
        activeDevice = device
        activeMedia = media
        phase = .connecting
        transportState = .transitioning
        baseTimeOffset = media.source.usesServerSideTimeSeek ? media.startPosition : 0
        currentTime = media.startPosition
        duration = media.duration
        volume = nil
        controlError = nil
        isSwitchingStream = false

        do {
            try await service.startCasting(device: device, media: media)
            guard sessionToken == token else { return false }
            rememberRecentDevice(device)
            phase = .casting
            transportState = .playing
            isSwitchingStream = false
            if device.renderingControlURL != nil {
                volume = try? await service.volume(device: device)
            }
            startPolling(token: token, device: device, media: media)
            return true
        } catch {
            guard sessionToken == token else { return false }
            let message = error.localizedDescription
            phase = .error(message)
            controlError = message
            transportState = .stopped
            isSwitchingStream = false
            return false
        }
    }

    /// 投屏期间热更新媒体源（如切换点播画质或直播清晰度）：保持当前投屏会话与进度上下文，失败不退出投屏模式。
    @discardableResult
    func hotUpdateMedia(_ media: CastMediaRequest) async -> Bool {
        guard let device = activeDevice, isCastModeActive else { return false }
        pollTask?.cancel()
        let token = UUID()
        sessionToken = token
        isSwitchingStream = true
        controlError = nil

        do {
            try await service.startCasting(device: device, media: media)
            guard sessionToken == token else { return false }
            activeMedia = media
            baseTimeOffset = media.source.usesServerSideTimeSeek ? media.startPosition : 0
            if media.duration > 0 { duration = media.duration }
            if media.source.usesServerSideTimeSeek { currentTime = media.startPosition }
            phase = .casting
            transportState = .playing
            isSwitchingStream = false
            startPolling(token: token, device: device, media: media)
            return true
        } catch {
            guard sessionToken == token else { return false }
            isSwitchingStream = false
            controlError = error.localizedDescription
            if let existing = activeMedia, phase == .casting {
                startPolling(token: token, device: device, media: existing)
            }
            return false
        }
    }

    func togglePlayPause() async {
        guard let device = activeDevice, phase == .casting else { return }
        controlError = nil
        do {
            if transportState.isPlaying {
                try await service.pause(device: device)
                transportState = .paused
            } else {
                try await service.play(device: device)
                transportState = .playing
            }
        } catch {
            controlError = error.localizedDescription
        }
    }

    func seek(to seconds: TimeInterval) async {
        guard let device = activeDevice,
              let media = activeMedia,
              media.kind.supportsSeeking,
              phase == .casting else { return }
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = clamped
        controlError = nil
        if media.source.usesServerSideTimeSeek {
            _ = await hotUpdateMedia(media.withStartPosition(clamped))
            return
        }
        do {
            try await service.seek(device: device, to: clamped)
        } catch {
            controlError = error.localizedDescription
        }
    }

    func adjustVolume(by delta: Int) async {
        guard let device = activeDevice, device.renderingControlURL != nil else { return }
        controlError = nil
        do {
            let current: Int
            if let existing = volume {
                current = existing
            } else {
                current = (try? await service.volume(device: device)) ?? 50
            }
            let target = max(0, min(100, current + delta))
            try await service.setVolume(device: device, to: target)
            volume = target
        } catch {
            controlError = error.localizedDescription
        }
    }

    @discardableResult
    func stopCasting() async -> TimeInterval {
        let resumeTime = currentTime
        let previousDevice = activeDevice
        sessionToken = UUID()
        pollTask?.cancel()
        pollTask = nil
        activeDevice = nil
        activeMedia = nil
        phase = .idle
        transportState = .stopped
        currentTime = 0
        duration = 0
        volume = nil
        controlError = nil
        isSwitchingStream = false

        if let previousDevice {
            try? await service.stop(device: previousDevice)
        }
        await service.stopServer()
        return resumeTime
    }

    func stopIfCasting(mediaID: String) async {
        guard activeMedia?.id == mediaID else { return }
        _ = await stopCasting()
    }

    private func rememberRecentDevice(_ device: CastDevice) {
        recentDevices.removeAll { $0.id == device.id || $0.location == device.location }
        recentDevices.insert(device, at: 0)
        if recentDevices.count > Self.maxRecentDevices {
            recentDevices = Array(recentDevices.prefix(Self.maxRecentDevices))
        }
        saveRecentDevices()
    }

    private func saveRecentDevices() {
        guard let recentDefaults, let data = try? JSONEncoder().encode(recentDevices) else { return }
        recentDefaults.set(data, forKey: Self.recentDevicesKey)
    }

    private static func loadRecentDevices(from defaults: UserDefaults?) -> [CastDevice] {
        guard let defaults,
              let data = defaults.data(forKey: recentDevicesKey),
              let decoded = try? JSONDecoder().decode([CastDevice].self, from: data) else {
            return []
        }
        return decoded
    }

    @discardableResult
    func replayCurrentMedia() async -> Bool {
        guard let device = activeDevice, let media = activeMedia else { return false }
        let restarted = CastMediaRequest(
            id: media.id,
            title: media.title,
            subtitle: media.subtitle,
            kind: media.kind,
            startPosition: 0,
            duration: media.duration,
            source: media.source
        )
        return await startCasting(device: device, media: restarted)
    }

    private func startPolling(token: UUID, device: CastDevice, media: CastMediaRequest) {
        pollTask?.cancel()
        pollTask = Task { [weak self, service, pollInterval] in
            var sawPlaying = false
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    break
                }
                guard !Task.isCancelled, let self, self.sessionToken == token else { break }

                if let state = try? await service.transportState(device: device) {
                    guard self.sessionToken == token else { break }
                    self.transportState = state
                    if state == .playing {
                        sawPlaying = true
                    } else if state == .stopped,
                              media.kind.supportsSeeking,
                              !self.isSwitchingStream,
                              self.endedNotifiedToken != token,
                              sawPlaying || (self.duration > 0 && self.currentTime >= self.duration - 2.5) {
                        self.endedNotifiedToken = token
                        self.onPlaybackEnded?(media.id)
                        break
                    }
                }
                if media.kind.supportsSeeking,
                   let info = try? await service.positionInfo(device: device) {
                    guard self.sessionToken == token else { break }
                    if !self.isScrubbing {
                        let resolved = media.source.usesServerSideTimeSeek
                            ? (self.baseTimeOffset + info.position)
                            : info.position
                        self.currentTime = self.duration > 0 ? min(resolved, self.duration) : resolved
                    }
                    if !media.source.usesServerSideTimeSeek, info.duration > 0 {
                        self.duration = info.duration
                    }
                }
            }
        }
    }
}
