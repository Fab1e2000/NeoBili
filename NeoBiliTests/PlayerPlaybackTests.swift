import XCTest
@testable import NeoBili

final class PlayerPlaybackTests: XCTestCase {
    func testFastStartConfigurationUsesThreeSecondBuffer() {
        let configuration = VideoPlaybackConfiguration.fastStart

        XCTAssertEqual(configuration.quality, 64)
        XCTAssertTrue(configuration.hardwareDecoding)
        XCTAssertEqual(configuration.initialBufferSeconds, 3)
        XCTAssertEqual(configuration.maxBufferBytes, 32 * 1024 * 1024)
        XCTAssertEqual(configuration.maxBackBufferBytes, 8 * 1024 * 1024)
        XCTAssertEqual(configuration.networkTimeoutSeconds, 10)
    }

    func testPlaybackConfigurationMapsToMPVOptions() {
        var configuration = VideoPlaybackConfiguration.fastStart
        configuration.hardwareDecoding = true
        configuration.initialBufferSeconds = 5
        configuration.maxBufferBytes = 123
        configuration.maxBackBufferBytes = 456
        configuration.networkTimeoutSeconds = 7

        let options = Dictionary(
            uniqueKeysWithValues: MPVPlaybackOptions.make(
                configuration: configuration,
                isSimulator: false,
                httpHeaderFields: "Referer: https://www.bilibili.com"
            )
        )

        XCTAssertEqual(options["hwdec"], "videotoolbox")
        XCTAssertEqual(options["vo"], "gpu-next")
        XCTAssertEqual(options["gpu-api"], "vulkan")
        XCTAssertEqual(options["gpu-context"], "moltenvk")
        XCTAssertEqual(options["cache-secs"], "5.0")
        XCTAssertEqual(options["cache-on-disk"], "no")
        XCTAssertEqual(options["demuxer-max-bytes"], "123")
        XCTAssertEqual(options["demuxer-max-back-bytes"], "456")
        XCTAssertEqual(options["network-timeout"], "7")
        XCTAssertEqual(options["video-sync"], "audio")
    }

    /// 模拟器没有 VideoToolbox 硬解通道，即便配置里开着硬解也要落到软解，
    /// 不然 mpv 初始化硬解设备会直接失败。
    func testSimulatorForcesSoftwareDecoding() {
        let configuration = VideoPlaybackConfiguration.fastStart
        let options = Dictionary(
            uniqueKeysWithValues: MPVPlaybackOptions.make(
                configuration: configuration,
                isSimulator: true,
                httpHeaderFields: "Referer: https://www.bilibili.com"
            )
        )

        XCTAssertEqual(options["hwdec"], "no")
    }

    func testDashSourceKeepsSeparateVideoAndAudioStreams() throws {
        let video = DashStream(
            id: 64,
            baseUrl: "https://cdn.example/video.mp4",
            backupUrl: ["https://backup.example/video.mp4"],
            bandwidth: 1_000_000,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            width: 1280,
            height: 720,
            frameRate: "30"
        )
        let audio = DashStream(
            id: 30280,
            baseUrl: "https://cdn.example/audio.m4s",
            backupUrl: ["https://backup.example/audio.m4s"],
            bandwidth: 192_000,
            mimeType: "audio/mp4",
            codecs: "mp4a.40.2",
            width: nil,
            height: nil,
            frameRate: nil
        )
        let payload = PlayURLData(
            quality: 64,
            acceptQuality: [64],
            acceptDescription: ["高清"],
            durl: nil,
            dash: DashPayload(duration: 120, video: [video], audio: [audio]),
            vVoucher: nil
        )

        let source = try PlaybackSourceBuilder.makeSource(
            from: payload,
            configuration: .fastStart
        )

        XCTAssertEqual(source.video.primary.absoluteString, video.baseUrl)
        XCTAssertEqual(source.audio?.primary.absoluteString, audio.baseUrl)
        XCTAssertEqual(source.video.backups.count, 1)
        XCTAssertEqual(source.audio?.backups.count, 1)
    }

    /// mpv 靠这个 EDL 伪协议地址把两条独立的流当成一个文件打开，长度前缀必须
    /// 按字节数（UTF-8）算，不能按字符数，否则多字节字符会把地址从中间截断。
    func testEdlURLJoinsVideoAndAudioByByteLength() throws {
        let video = PlaybackStream(
            primary: try XCTUnwrap(URL(string: "https://cdn.example/video.m4s")),
            backups: []
        )
        let audio = PlaybackStream(
            primary: try XCTUnwrap(URL(string: "https://cdn.example/audio.m4s")),
            backups: []
        )
        let source = PlaybackSource(video: video, audio: audio, duration: 10)

        let edl = PlaybackSourceBuilder.edlURL(for: source)

        XCTAssertEqual(
            edl,
            "edl://!no_chapters;%\(video.primary.absoluteString.utf8.count)%\(video.primary.absoluteString);"
                + "!new_stream;!no_chapters;%\(audio.primary.absoluteString.utf8.count)%\(audio.primary.absoluteString)"
        )
    }

    /// 服务端合并好的文件没有独立的音轨，直接是它自己的地址，不需要 EDL 包装。
    func testEdlURLReturnsPlainURLWhenThereIsNoSeparateAudio() throws {
        let video = PlaybackStream(
            primary: try XCTUnwrap(URL(string: "https://cdn.example/muxed.mp4")),
            backups: []
        )
        let source = PlaybackSource(video: video, audio: nil, duration: 10)

        XCTAssertEqual(PlaybackSourceBuilder.edlURL(for: source), video.primary.absoluteString)
    }

    func testSourceCandidatesTryPrimaryThenBackupPairs() throws {
        let video = PlaybackStream(
            primary: try XCTUnwrap(URL(string: "https://cdn.example/video")),
            backups: [try XCTUnwrap(URL(string: "https://backup.example/video"))]
        )
        let audio = PlaybackStream(
            primary: try XCTUnwrap(URL(string: "https://cdn.example/audio")),
            backups: [try XCTUnwrap(URL(string: "https://backup.example/audio"))]
        )
        let source = PlaybackSource(video: video, audio: audio, duration: 10)

        XCTAssertEqual(source.candidates.count, 4)
        XCTAssertEqual(source.candidates[0].video.primary, video.primary)
        XCTAssertEqual(source.candidates[0].audio?.primary, audio.primary)
        XCTAssertEqual(source.candidates[3].video.primary, video.backups[0])
        XCTAssertEqual(source.candidates[3].audio?.primary, audio.backups[0])
    }

    func testQualityWithoutLowerRepresentationUsesLowestAvailableStream() {
        let streams = [
            DashStream(
                id: 80,
                baseUrl: "https://cdn.example/1080p",
                backupUrl: nil,
                bandwidth: 2_000_000,
                mimeType: "video/mp4",
                codecs: "avc1",
                width: 1920,
                height: 1080,
                frameRate: "30"
            ),
            DashStream(
                id: 112,
                baseUrl: "https://cdn.example/4k",
                backupUrl: nil,
                bandwidth: 8_000_000,
                mimeType: "video/mp4",
                codecs: "avc1",
                width: 3840,
                height: 2160,
                frameRate: "30"
            )
        ]

        XCTAssertEqual(
            PlaybackSourceBuilder.bestVideoStream(streams, preferredQuality: 64)?.id,
            80
        )
    }

    /// mpv/FFmpeg 什么编码都能解，这里的偏好只是"同画质下优先选兼容性、
    /// 硬解效率更好的编码"，不是能不能播的问题。
    func testSameQualityPrefersAVCInsteadOfBandwidth() {
        let streams = [
            makeDashStream(codecs: "hev1.1.6.L120.90", bandwidth: 4_000_000),
            makeDashStream(codecs: "av01.0.08M.08", bandwidth: 3_000_000),
            makeDashStream(codecs: "avc1.640028", bandwidth: 1_000_000)
        ]

        XCTAssertEqual(
            PlaybackSourceBuilder.bestVideoStream(streams, preferredQuality: 64)?.codecs,
            "avc1.640028"
        )
    }

    func testSourcePrefersUposBackupOverMCDNBaseURL() throws {
        let video = DashStream(
            id: 64,
            baseUrl: "https://video.mcdn.bilivideo.cn/v1/resource/upgcxcode/video.m4s",
            backupUrl: [
                "https://edge.example.com/upgcxcode/video.m4s",
                "https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video.m4s"
            ],
            bandwidth: 1_000_000,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            width: 1280,
            height: 720,
            frameRate: "30"
        )
        let audio = DashStream(
            id: 30280,
            baseUrl: "https://audio.mcdn.bilivideo.cn/v1/resource/upgcxcode/audio.m4s",
            backupUrl: ["https://upos-sz-mirrorali.bilivideo.com/upgcxcode/audio.m4s"],
            bandwidth: 192_000,
            mimeType: "audio/mp4",
            codecs: "mp4a.40.2",
            width: nil,
            height: nil,
            frameRate: nil
        )
        let payload = PlayURLData(
            quality: 64,
            acceptQuality: [64],
            acceptDescription: ["高清"],
            durl: nil,
            dash: DashPayload(duration: 10, video: [video], audio: [audio]),
            vVoucher: nil
        )

        let source = try PlaybackSourceBuilder.makeSource(
            from: payload,
            configuration: .fastStart
        )

        XCTAssertEqual(source.video.primary.host, "upos-sz-mirrorcos.bilivideo.com")
        XCTAssertEqual(source.audio?.primary.host, "upos-sz-mirrorali.bilivideo.com")
    }

    /// 退出全屏那一瞬间容器还是横屏尺寸。内联高度按短边算，所以旋转前后是同
    /// 一个值，画面不会先撑满再弹回来。
    func testInlineVideoHeightIsStableAcrossRotation() {
        let portrait = VideoPage.inlineVideoHeight(for: CGSize(width: 393, height: 759))
        let landscape = VideoPage.inlineVideoHeight(for: CGSize(width: 852, height: 393))

        XCTAssertEqual(portrait, landscape)
        XCTAssertEqual(portrait, (393.0 * 9.0 / 16.0).rounded())
    }

    private func makeDashStream(codecs: String, bandwidth: Int) -> DashStream {
        DashStream(
            id: 64,
            baseUrl: "https://cdn.example/\(codecs)",
            backupUrl: nil,
            bandwidth: bandwidth,
            mimeType: "video/mp4",
            codecs: codecs,
            width: 1280,
            height: 720,
            frameRate: "30"
        )
    }

    @MainActor
    func testStopIgnoresLatePlaybackURLResult() async {
        let payload = PlayURLData(
            quality: 64,
            acceptQuality: [64],
            acceptDescription: ["高清"],
            durl: [
                DurlItem(
                    url: "https://cdn.example/video.mp4",
                    backupUrl: nil,
                    length: 10_000,
                    size: nil
                )
            ],
            dash: nil,
            vVoucher: nil
        )
        let viewModel = PlayerViewModel(
            bvid: "BV1TEST",
            cid: 1,
            playbackURLLoader: { _, _ in
                try? await Task.sleep(for: .milliseconds(20))
                return payload
            }
        )

        let loadTask = Task { await viewModel.load() }
        await Task.yield()
        viewModel.stop()
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.hasRenderedFirstFrame)
    }

    @MainActor
    func testLateDismissalDoesNotCloseNewlyOpenedVideo() {
        let store = NowPlayingStore()

        store.open(VideoDetailRoute(bvid: "BV1FIRST"), from: "BV1FIRST")
        store.close()
        store.open(VideoDetailRoute(bvid: "BV1SECOND"), from: "BV1SECOND")

        // Simulate the first page's delayed onDisappear callback arriving
        // after the second card has already opened.
        store.finishDismissal()

        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.route?.bvid, "BV1SECOND")

        store.close()
    }

    func testPlayerSurfaceKeepsOneLandscapeDrawableSizeAcrossRotation() {
        let portrait = PlayerSurfaceGeometry.stableDrawableSize(
            for: CGSize(width: 1206, height: 2622)
        )
        let landscape = PlayerSurfaceGeometry.stableDrawableSize(
            for: CGSize(width: 2622, height: 1206)
        )

        XCTAssertEqual(portrait, CGSize(width: 2622, height: 1206))
        XCTAssertEqual(landscape, portrait)
    }

    func testStablePlayerSurfaceIsCenteredAndAspectFilledInInlineContainer() {
        let surface = PlayerSurfaceGeometry.pointSize(
            for: CGSize(width: 2622, height: 1206),
            displayScale: 3
        )
        let scale = PlayerSurfaceGeometry.presentationScale(
            surfaceSize: surface,
            containerSize: CGSize(width: 402, height: 226)
        )

        XCTAssertEqual(surface, CGSize(width: 874, height: 402))
        XCTAssertEqual(scale, 226.0 / 402.0, accuracy: 0.000_001)
        XCTAssertEqual(surface.height * scale, 226, accuracy: 0.000_001)
        XCTAssertGreaterThan(surface.width * scale, 402)
    }
}
