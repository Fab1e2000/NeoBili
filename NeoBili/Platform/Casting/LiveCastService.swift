#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

/// 生产环境的 DLNA 投屏服务组装：SSDP 发现 + UPnP SOAP 控制 + 本地 HTTP Range 代理 + 离线双轨快速封装。
final class LiveCastBackend: Sendable {
    private let controlClient: UPnPControlClient
    private let proxyServer: LocalMediaProxyServer
    private let muxer: OfflineCastMuxer

    init(
        controlClient: UPnPControlClient = UPnPControlClient(),
        proxyServer: LocalMediaProxyServer = LocalMediaProxyServer(),
        muxer: OfflineCastMuxer = OfflineCastMuxer()
    ) {
        self.controlClient = controlClient
        self.proxyServer = proxyServer
        self.muxer = muxer
    }

    func makeService() -> CastService {
        CastService(
            discoverDevicesOperation: { [controlClient] timeout in
                let locations = try await SSDPDiscovery.discoverLocations(timeout: timeout)
                return await withTaskGroup(of: CastDevice?.self) { group in
                    for location in locations {
                        group.addTask {
                            try? await controlClient.fetchDeviceDescription(from: location)
                        }
                    }
                    var seen = Set<String>()
                    var devices: [CastDevice] = []
                    for await device in group {
                        if let device, seen.insert(device.id).inserted {
                            devices.append(device)
                        }
                    }
                    return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                }
            },
            inspectDeviceOperation: { [controlClient] location in
                try await controlClient.fetchDeviceDescription(from: location)
            },
            startCastingOperation: { [controlClient, proxyServer, muxer] device, media in
                guard let host = LocalNetworkAddress.lanIPv4Address() else {
                    throw CastError.localNetworkUnavailable
                }
                let route: LocalMediaProxyServer.Route
                let mimeType: String
                switch media.source {
                case .remoteHTTP(let url, let headers, let remoteMime):
                    let isHLS = remoteMime.localizedCaseInsensitiveContains("mpegurl")
                        || url.pathExtension.lowercased() == "m3u8"
                    route = .remoteMedia(url: url, headers: headers, mimeType: remoteMime, isHLS: isHLS)
                    mimeType = isHLS ? "application/vnd.apple.mpegurl" : remoteMime
                case .remoteDualTrack(let videoURL, let audioURL, let headers):
                    route = .remoteDualTrack(
                        videoURL: videoURL,
                        audioURL: audioURL,
                        headers: headers,
                        startPosition: media.startPosition
                    )
                    mimeType = "video/mp4"
                case .localFile(let url, let localMime):
                    route = .localFile(url: url, mimeType: localMime)
                    mimeType = localMime
                case .localDualTrack(let videoURL, let audioURL):
                    let muxedURL = try await muxer.muxToMP4(videoURL: videoURL, audioURL: audioURL)
                    route = .localFile(url: muxedURL, mimeType: "video/mp4")
                    mimeType = "video/mp4"
                }

                let proxyURL = try await proxyServer.publish(route, host: host)
                try? await controlClient.stop(device: device)
                try await controlClient.setAVTransportURI(
                    device: device,
                    mediaURL: proxyURL,
                    title: media.title,
                    mimeType: mimeType,
                    isLive: media.kind == .live
                )
                try await controlClient.play(device: device)
                if media.kind.supportsSeeking, !media.source.usesServerSideTimeSeek, media.startPosition >= 3 {
                    // 部分电视起播后需短暂进入 PLAYING/TRANSITIONING 状态才接受 Seek。
                    try? await Task.sleep(for: .milliseconds(500))
                    try? await controlClient.seek(device: device, to: media.startPosition)
                }
            },
            playOperation: { [controlClient] device in
                try await controlClient.play(device: device)
            },
            pauseOperation: { [controlClient] device in
                try await controlClient.pause(device: device)
            },
            stopOperation: { [controlClient] device in
                try await controlClient.stop(device: device)
            },
            seekOperation: { [controlClient] device, seconds in
                try await controlClient.seek(device: device, to: seconds)
            },
            positionInfoOperation: { [controlClient] device in
                try await controlClient.positionInfo(device: device)
            },
            transportStateOperation: { [controlClient] device in
                try await controlClient.transportState(device: device)
            },
            volumeOperation: { [controlClient] device in
                try await controlClient.volume(device: device)
            },
            setVolumeOperation: { [controlClient] device, level in
                try await controlClient.setVolume(device: device, to: level)
            },
            stopServerOperation: { [proxyServer, muxer] in
                await proxyServer.stop()
                await muxer.cleanup()
            }
        )
    }
}
