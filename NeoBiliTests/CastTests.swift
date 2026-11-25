import AVFoundation
import Foundation
import Network
import Synchronization
import XCTest
@testable import NeoBili
@testable import NeoBiliDomain

final class CastTests: XCTestCase {
    // MARK: - DLNA XML & SSDP

    func testSSDPResponseParsing() {
        let raw = """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        location: http://192.168.1.50:49152/description.xml\r
        ST: urn:schemas-upnp-org:service:AVTransport:1\r
        USN: uuid:1234-5678::urn:schemas-upnp-org:service:AVTransport:1\r
        SERVER: Macast/0.7 UPnP/1.0\r
        \r
        """
        let parsed = DLNAXMLCodec.parseSSDPResponse(raw)
        XCTAssertEqual(parsed?.location, URL(string: "http://192.168.1.50:49152/description.xml"))
        XCTAssertEqual(parsed?.st, "urn:schemas-upnp-org:service:AVTransport:1")
        XCTAssertEqual(parsed?.usn, "uuid:1234-5678::urn:schemas-upnp-org:service:AVTransport:1")
        XCTAssertNil(DLNAXMLCodec.parseSSDPResponse("HTTP/1.1 200 OK\r\nLOCATION: file:///etc/passwd\r\n\r\n"))
    }

    func testDeviceDescriptionParsingAndLegacyControlURLNormalization() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <friendlyName>客厅电视 (Macast)</friendlyName>
            <manufacturer>Macast</manufacturer>
            <modelName>MPV Renderer</modelName>
            <UDN>uuid:macast-001</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <controlURL>upnp/control/AVTransport1</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <controlURL>/upnp/control/RenderingControl1</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
        let location = URL(string: "http://192.168.1.50:49152/dlna/desc.xml")!
        let device = try DLNAXMLCodec.parseDeviceDescription(Data(xml.utf8), location: location)
        XCTAssertEqual(device.id, "uuid:macast-001")
        XCTAssertEqual(device.name, "客厅电视 (Macast)")
        XCTAssertEqual(device.manufacturer, "Macast")
        XCTAssertEqual(device.modelName, "MPV Renderer")
        XCTAssertEqual(device.avTransportControlURL, URL(string: "http://192.168.1.50:49152/upnp/control/AVTransport1"))
        XCTAssertEqual(device.renderingControlURL, URL(string: "http://192.168.1.50:49152/upnp/control/RenderingControl1"))
    }

    func testSetAVTransportURIEscapesSpecialXMLCharacters() {
        let mediaURL = URL(string: "http://192.168.1.2:8080/cast/abc/media.mp4?a=1&b=2")!
        let envelope = DLNAXMLCodec.setAVTransportURIEnvelope(
            mediaURL: mediaURL,
            title: "Tom & Jerry <4K> \"Special\"",
            mimeType: "video/mp4",
            isLive: false
        )
        XCTAssertTrue(envelope.contains("http://192.168.1.2:8080/cast/abc/media.mp4?a=1&amp;b=2"))
        // DIDL-Lite 内部及外层 SOAP 双重转义，避免 AirPin 等接收端 XML 解析崩溃。
        XCTAssertTrue(envelope.contains("&amp;amp;"))
        XCTAssertTrue(envelope.contains("&amp;lt;4K&amp;gt;"))
        XCTAssertFalse(envelope.contains("Tom & Jerry <4K>"))
    }

    func testSOAPResponseParsing() {
        let positionXML = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <TrackDuration>00:12:34</TrackDuration>
              <RelTime>00:03:21.5</RelTime>
            </u:GetPositionInfoResponse>
          </s:Body>
        </s:Envelope>
        """
        let pos = DLNAXMLCodec.parsePositionInfo(Data(positionXML.utf8))
        XCTAssertEqual(pos.duration, 12 * 60 + 34, accuracy: 0.01)
        XCTAssertEqual(pos.position, 3 * 60 + 21.5, accuracy: 0.01)
        XCTAssertEqual(DLNAXMLCodec.formatTime(3665), "01:01:05")

        let stateXML = """
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>
            </u:GetTransportInfoResponse>
          </s:Body>
        </s:Envelope>
        """
        XCTAssertEqual(DLNAXMLCodec.parseTransportState(Data(stateXML.utf8)), .paused)

        let volumeXML = "<CurrentVolume>42</CurrentVolume>"
        XCTAssertEqual(DLNAXMLCodec.parseVolume(Data(volumeXML.utf8)), 42)
    }

    // MARK: - LocalMediaProxyServer

    func testByteRangeParsing() {
        XCTAssertEqual(LocalMediaProxyServer.parseByteRange("bytes=0-9", totalLength: 100), .init(start: 0, end: 9))
        XCTAssertEqual(LocalMediaProxyServer.parseByteRange("bytes=90-", totalLength: 100), .init(start: 90, end: 99))
        XCTAssertEqual(LocalMediaProxyServer.parseByteRange("bytes=-10", totalLength: 100), .init(start: 90, end: 99))
        XCTAssertEqual(LocalMediaProxyServer.parseByteRange("bytes=50-500", totalLength: 100), .init(start: 50, end: 99))
        XCTAssertNil(LocalMediaProxyServer.parseByteRange("bytes=100-120", totalLength: 100))
        XCTAssertNil(LocalMediaProxyServer.parseByteRange("items=0-10", totalLength: 100))
    }

    func testHLSPlaylistRewriting() {
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-MAP:URI="init.m4s"
        #EXTINF:2.0,
        seg001.m4s?token=abc
        #EXTINF:2.0,
        https://cdn.example.com/live/seg002.m4s
        """
        let baseURL = URL(string: "https://live.example.com/room/index.m3u8")!
        let rewritten = LocalMediaProxyServer.rewriteHLSPlaylist(
            playlist,
            baseURL: baseURL,
            proxyPrefix: "http://192.168.1.5:9000/cast/tok"
        )
        let lines = rewritten.components(separatedBy: .newlines)
        XCTAssertTrue(lines[2].contains("URI=\"http://192.168.1.5:9000/cast/tok/seg?u="))
        XCTAssertTrue(lines[4].hasPrefix("http://192.168.1.5:9000/cast/tok/seg?u="))
        XCTAssertTrue(lines[6].hasPrefix("http://192.168.1.5:9000/cast/tok/seg?u="))

        let encodedSeg1 = String(lines[4].split(separator: "=").last ?? "")
        XCTAssertEqual(
            LocalMediaProxyServer.decodeBase64URL(encodedSeg1),
            URL(string: "https://live.example.com/room/seg001.m4s?token=abc")
        )
        let encodedSeg2 = String(lines[6].split(separator: "=").last ?? "")
        XCTAssertEqual(
            LocalMediaProxyServer.decodeBase64URL(encodedSeg2),
            URL(string: "https://cdn.example.com/live/seg002.m4s")
        )
    }

    func testLocalMediaProxyServesLocalFileWithHeadAndRange() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("neobili-cast-test-\(UUID().uuidString).mp4")
        let content = Data("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        try content.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let server = LocalMediaProxyServer()
        defer { Task { await server.stop() } }

        let publishedURL = try await server.publish(.localFile(url: tempFile, mimeType: "video/mp4"), host: "127.0.0.1")

        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)

        // 1. HEAD 请求
        var headReq = URLRequest(url: publishedURL)
        headReq.httpMethod = "HEAD"
        let (headData, headResp) = try await session.data(for: headReq)
        let headHTTP = try XCTUnwrap(headResp as? HTTPURLResponse)
        XCTAssertEqual(headHTTP.statusCode, 200)
        XCTAssertEqual(headHTTP.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        XCTAssertEqual(headHTTP.value(forHTTPHeaderField: "Content-Length"), "\(content.count)")
        XCTAssertTrue(headData.isEmpty)

        // 2. Range 206 请求
        var rangeReq = URLRequest(url: publishedURL)
        rangeReq.setValue("bytes=10-15", forHTTPHeaderField: "Range")
        let (rangeData, rangeResp) = try await session.data(for: rangeReq)
        let rangeHTTP = try XCTUnwrap(rangeResp as? HTTPURLResponse)
        XCTAssertEqual(rangeHTTP.statusCode, 206)
        XCTAssertEqual(rangeHTTP.value(forHTTPHeaderField: "Content-Range"), "bytes 10-15/\(content.count)")
        XCTAssertEqual(String(decoding: rangeData, as: UTF8.self), "ABCDEF")

        // 3. 无效 token 返回 404
        let invalidURL = URL(string: "http://127.0.0.1:\(publishedURL.port ?? 0)/cast/invalid/media.mp4")!
        let (_, invalidResp) = try await session.data(from: invalidURL)
        XCTAssertEqual((invalidResp as? HTTPURLResponse)?.statusCode, 404)
    }

    func testRemoteProxyForwardsMultiChunkRangeAndHead() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp4")
        let content = Data((0..<1_048_576).map { UInt8($0 % 251) })
        try content.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let upstream = LocalMediaProxyServer()
        let proxy = LocalMediaProxyServer()
        defer { Task { await proxy.stop(); await upstream.stop() } }
        let origin = try await upstream.publish(.localFile(url: file, mimeType: "video/mp4"), host: "127.0.0.1")
        let url = try await proxy.publish(.remoteMedia(url: origin, headers: [:], mimeType: "video/mp4", isHLS: false),
                                          host: "127.0.0.1")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("bytes=7-900006", forHTTPHeaderField: "Range")
        let (bytes, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 7-900006/1048576")
        XCTAssertEqual(bytes, Data(content[7...900006]))
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), "video/mp4")

        request.httpMethod = "HEAD"
        let (headBytes, headResponse) = try await session.data(for: request)
        let head = try XCTUnwrap(headResponse as? HTTPURLResponse)
        XCTAssertEqual(head.statusCode, 206)
        XCTAssertEqual(head.value(forHTTPHeaderField: "Content-Length"), "900000")
        XCTAssertTrue(headBytes.isEmpty)
    }

    // MARK: - CastSessionModel

    @MainActor
    func testCastSessionLifecycleAndControls() async throws {
        let device = CastDevice(
            id: "dev-1",
            name: "Macast",
            location: URL(string: "http://192.168.1.9:5000/desc.xml")!,
            avTransportControlURL: URL(string: "http://192.168.1.9:5000/av")!,
            renderingControlURL: URL(string: "http://192.168.1.9:5000/rc")!
        )
        let recorder = CastCallRecorder()
        let service = CastService(
            discoverDevicesOperation: { _ in [device] },
            inspectDeviceOperation: { _ in device },
            startCastingOperation: { dev, media in await recorder.record("start:\(dev.id):\(media.id)") },
            playOperation: { _ in await recorder.record("play") },
            pauseOperation: { _ in await recorder.record("pause") },
            stopOperation: { _ in await recorder.record("stop") },
            seekOperation: { _, seconds in await recorder.record("seek:\(Int(seconds))") },
            positionInfoOperation: { _ in CastPlaybackPosition(position: 45, duration: 120) },
            transportStateOperation: { _ in .playing },
            volumeOperation: { _ in 40 },
            setVolumeOperation: { _, vol in await recorder.record("vol:\(vol)") },
            stopServerOperation: { await recorder.record("stopServer") }
        )

        let model = CastSessionModel(service: service, pollInterval: .seconds(60), recentDefaults: nil)
        let media = CastMediaRequest(
            id: "video:BV1xx:1",
            title: "测试视频",
            kind: .video,
            startPosition: 12,
            source: .remoteHTTP(url: URL(string: "https://example.com/v.mp4")!, headers: [:], mimeType: "video/mp4")
        )

        let started = await model.startCasting(device: device, media: media)
        XCTAssertTrue(started)
        XCTAssertEqual(model.phase, .casting)
        XCTAssertTrue(model.isCasting(mediaID: "video:BV1xx:1"))
        XCTAssertEqual(model.volume, 40)

        await model.togglePlayPause()
        XCTAssertEqual(model.transportState, .paused)
        await model.togglePlayPause()
        XCTAssertEqual(model.transportState, .playing)

        await model.seek(to: 66)
        XCTAssertEqual(model.currentTime, 66)

        await model.adjustVolume(by: 10)
        XCTAssertEqual(model.volume, 50)

        let resume = await model.stopCasting()
        XCTAssertEqual(resume, 66)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.isActive)

        let calls = await recorder.calls
        XCTAssertEqual(calls, [
            "start:dev-1:video:BV1xx:1",
            "pause",
            "play",
            "seek:66",
            "vol:50",
            "stop",
            "stopServer"
        ])
    }

    @MainActor
    func testRecentDevicesPersistenceAndRemoval() async throws {
        let suiteName = "neobili.cast.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let device = CastDevice(
            id: "kodi-1",
            name: "Kodi (Mac)",
            manufacturer: "XBMC Foundation",
            modelName: "Kodi",
            location: URL(string: "http://10.208.23.6:1680/desc.xml")!,
            avTransportControlURL: URL(string: "http://10.208.23.6:1680/AVTransport/control")!
        )
        let service = CastService(inspectDeviceOperation: { _ in device })
        let model = CastSessionModel(service: service, recentDefaults: defaults)

        _ = try await model.addManualDevice(address: "http://10.208.23.6:1680/desc.xml")
        XCTAssertEqual(model.recentDevices, [device])

        // 重新构造模型，验证从持久化存储恢复。
        let restored = CastSessionModel(service: service, recentDefaults: defaults)
        XCTAssertEqual(restored.recentDevices, [device])

        restored.removeRecentDevice(device)
        XCTAssertTrue(restored.recentDevices.isEmpty)
        let afterDelete = CastSessionModel(service: service, recentDefaults: defaults)
        XCTAssertTrue(afterDelete.recentDevices.isEmpty)
    }

    func testOfflineCastMuxerHandlesM4SExtension() async throws {
        let bundle = Bundle(for: Self.self)
        let videoFixture = try XCTUnwrap(
            bundle.url(forResource: "offline-video", withExtension: "mp4", subdirectory: "Fixtures/Offline")
                ?? bundle.url(forResource: "offline-video", withExtension: "mp4")
        )
        let audioFixture = try XCTUnwrap(
            bundle.url(forResource: "offline-audio", withExtension: "m4a", subdirectory: "Fixtures/Offline")
                ?? bundle.url(forResource: "offline-audio", withExtension: "m4a")
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neobili-m4s-mux-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoM4S = tempDir.appendingPathComponent("video-0.m4s")
        let audioM4S = tempDir.appendingPathComponent("audio.m4s")
        try FileManager.default.copyItem(at: videoFixture, to: videoM4S)
        try FileManager.default.copyItem(at: audioFixture, to: audioM4S)

        let muxer = OfflineCastMuxer(directory: tempDir.appendingPathComponent("out", isDirectory: true))
        let muxedURL = try await muxer.muxToMP4(videoURL: videoM4S, audioURL: audioM4S)
        XCTAssertTrue(FileManager.default.fileExists(atPath: muxedURL.path))

        let asset = AVURLAsset(url: muxedURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(videoTracks.isEmpty)
        XCTAssertFalse(audioTracks.isEmpty)
        await muxer.cleanup()
    }

    @MainActor
    func testCastModePersistsAndSwitchesMediaOnSameDevice() async {
        let device = CastDevice(
            id: "kodi-mode",
            name: "Kodi",
            location: URL(string: "http://10.208.23.6:1680/desc.xml")!,
            avTransportControlURL: URL(string: "http://10.208.23.6:1680/AVTransport")!
        )
        let recorder = CastCallRecorder()
        let service = CastService(
            startCastingOperation: { dev, media in await recorder.record("cast:\(dev.id):\(media.id)") },
            stopOperation: { _ in await recorder.record("stop") },
            stopServerOperation: { await recorder.record("stopServer") }
        )

        let model = CastSessionModel(service: service, pollInterval: .seconds(60), recentDefaults: nil)
        let first = CastMediaRequest(
            id: "video:BV1:1",
            title: "视频一",
            kind: .video,
            source: .remoteHTTP(url: URL(string: "https://example.com/1.mp4")!, headers: [:], mimeType: "video/mp4")
        )
        let second = CastMediaRequest(
            id: "live:1001",
            title: "直播二",
            kind: .live,
            source: .remoteHTTP(url: URL(string: "https://example.com/live.m3u8")!, headers: [:], mimeType: "application/vnd.apple.mpegurl")
        )

        let firstStarted = await model.startCasting(device: device, media: first)
        XCTAssertTrue(firstStarted)
        XCTAssertTrue(model.isCastModeActive)
        XCTAssertTrue(model.isCasting(mediaID: "video:BV1:1"))

        let switched = await model.startCasting(device: device, media: second)
        XCTAssertTrue(switched)
        XCTAssertTrue(model.isCastModeActive)
        XCTAssertFalse(model.isCasting(mediaID: "video:BV1:1"))
        XCTAssertTrue(model.isCasting(mediaID: "live:1001"))

        _ = await model.stopCasting()
        XCTAssertFalse(model.isCastModeActive)
        let calls = await recorder.calls
        XCTAssertEqual(calls, ["cast:kodi-mode:video:BV1:1", "cast:kodi-mode:live:1001", "stop", "stopServer"])
    }

    func testDASHRemuxCancellationInterruptsOpenBeforeUpstreamResponds() async throws {
        let queue = DispatchQueue(label: "test.cast.stalled-origin")
        let listener = try NWListener(using: .tcp)
        let ready = expectation(description: "upstream listening")
        let accepted = expectation(description: "upstream accepted input request")
        let stopped = expectation(description: "remux returned after cancellation")
        let cancelled = Mutex(false)
        let peer = Mutex<NWConnection?>(nil)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { connection in
            peer.withLock { $0 = connection }
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                accepted.fulfill()
            }
        }
        listener.start(queue: queue)
        defer {
            cancelled.withLock { $0 = true }
            listener.cancel()
            peer.withLock { $0?.cancel() }
        }
        await fulfillment(of: [ready], timeout: 2)
        let port = try XCTUnwrap(listener.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/stalled.mp4"))
        DispatchQueue.global(qos: .userInitiated).async {
            defer { stopped.fulfill() }
            do {
                try DASHCastRemuxer.stream(videoURL: url, audioURL: nil, headers: [:],
                                         isCancelled: { cancelled.withLock { $0 } }) { _ in
                    XCTFail("The stalled upstream cannot produce media")
                    return false
                }
            } catch {
                XCTFail("Cancellation should exit quietly: \(error)")
            }
        }
        await fulfillment(of: [accepted], timeout: 3)
        cancelled.withLock { $0 = true }
        await fulfillment(of: [stopped], timeout: 3)
    }

    func testDASHCastRemuxerProducesValidFragmentedMP4FromDualTracks() async throws {
        let bundle = Bundle(for: Self.self)
        let videoFixture = try XCTUnwrap(
            bundle.url(forResource: "offline-video", withExtension: "mp4", subdirectory: "Fixtures/Offline")
                ?? bundle.url(forResource: "offline-video", withExtension: "mp4")
        )
        let audioFixture = try XCTUnwrap(
            bundle.url(forResource: "offline-audio", withExtension: "m4a", subdirectory: "Fixtures/Offline")
                ?? bundle.url(forResource: "offline-audio", withExtension: "m4a")
        )

        var output = Data()
        try DASHCastRemuxer.stream(
            videoURL: videoFixture,
            audioURL: audioFixture,
            headers: [:],
            startPosition: 0
        ) { chunk in
            output.append(chunk)
            return true
        }

        XCTAssertGreaterThan(output.count, 1024)
        XCTAssertNotNil(output.range(of: Data("ftyp".utf8)))
        XCTAssertNotNil(output.range(of: Data("moov".utf8)))
        XCTAssertNotNil(output.range(of: Data("moof".utf8)))

        let tempOutput = FileManager.default.temporaryDirectory
            .appendingPathComponent("neobili-dash-remux-\(UUID().uuidString).mp4")
        try output.write(to: tempOutput)
        defer { try? FileManager.default.removeItem(at: tempOutput) }

        let asset = AVURLAsset(url: tempOutput)
        let vTracks = try await asset.loadTracks(withMediaType: .video)
        let aTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(vTracks.isEmpty)
        XCTAssertFalse(aTracks.isEmpty)
    }

    @MainActor
    func testHotUpdateAndServerSideTimeSeekKeepCastMode() async {
        let device = CastDevice(
            id: "kodi-dash",
            name: "Kodi",
            location: URL(string: "http://10.208.23.6:1680/desc.xml")!,
            avTransportControlURL: URL(string: "http://10.208.23.6:1680/AVTransport")!
        )
        let recorder = CastCallRecorder()
        let service = CastService(
            startCastingOperation: { _, media in
                await recorder.record("cast:\(media.title)@\(Int(media.startPosition))")
            },
            stopOperation: { _ in },
            stopServerOperation: {}
        )

        let model = CastSessionModel(service: service, pollInterval: .seconds(60), recentDefaults: nil)
        let media = CastMediaRequest(
            id: "video:BV3:1",
            title: "4K",
            kind: .video,
            startPosition: 10,
            duration: 300,
            source: .remoteDualTrack(
                videoURL: URL(string: "https://example.com/v.m4s")!,
                audioURL: URL(string: "https://example.com/a.m4s")!,
                headers: [:]
            )
        )

        let started = await model.startCasting(device: device, media: media)
        XCTAssertTrue(started)
        XCTAssertEqual(model.duration, 300)
        XCTAssertEqual(model.currentTime, 10)

        await model.seek(to: 125)
        XCTAssertEqual(model.currentTime, 125)
        let calls = await recorder.calls
        XCTAssertEqual(calls, ["cast:4K@10", "cast:4K@125"])
    }

    @MainActor
    func testLivePlayerPrefersHLSForCasting() async {
        let room = LiveRoom(roomID: 1001, title: "测试直播", username: "主播")
        let flv = LiveStreamCandidate(
            url: URL(string: "https://live.example.com/stream.flv")!,
            protocolName: "http_stream",
            formatName: "flv",
            codecName: "avc",
            quality: 10000
        )
        let hls = LiveStreamCandidate(
            url: URL(string: "https://live.example.com/stream.m3u8")!,
            protocolName: "http_hls",
            formatName: "fmp4",
            codecName: "avc",
            quality: 10000
        )
        let playback = LivePlayback(
            roomID: 1001,
            liveStatus: 1,
            isPortrait: false,
            qualities: [LiveQuality(id: 10000, name: "原画")],
            candidates: [flv, hls]
        )
        let model = LivePlayerModel(
            room: room,
            roomLoader: { _ in room },
            playbackLoader: { _, _ in playback },
            sourceOpener: { _, _, _ in },
            publishesSystemMedia: false
        )
        await model.load()
        XCTAssertEqual(model.preferredCastCandidate()?.url, hls.url)
    }
}

private actor CastCallRecorder {
    private(set) var calls: [String] = []
    func record(_ call: String) {
        calls.append(call)
    }
}
