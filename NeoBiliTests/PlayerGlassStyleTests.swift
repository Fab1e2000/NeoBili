import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Static controls are hosted on the real iPhone window. The controls API is
/// injected by the tests below; no PlayerViewModel/MPV/network is needed.
@MainActor
final class PlayerGlassStyleTests: XCTestCase {
    func testProgressUpdatesDoNotRebuildMenuContentOnRealDevice() async throws {
        let host = try PlayerGlassSnapshotHost()
        defer { host.close() }
        let progress = PlayerProgressIsolationState()
        let recorder = PlayerProgressIsolationRecorder()
        try await host.show(PlayerProgressIsolationFixture(progress: progress, recorder: recorder))
        let initialMenus = recorder.menuBuilds
        XCTAssertGreaterThan(initialMenus, 0)
        XCTAssertEqual(recorder.lastPosition, 0)

        for tick in 1...10 {
            progress.position = Double(tick)
            progress.buffered = Double(tick + 20)
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(recorder.lastPosition, 10, "The timeline must continue reading live progress")
        XCTAssertEqual(recorder.lastBuffered, 30)
        XCTAssertEqual(recorder.menuBuilds, initialMenus,
                       "Playback ticks must not rebuild native menu content")

        progress.quality = 64
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(recorder.menuBuilds, initialMenus,
                             "Real quality changes must still update menu content")
        XCTAssertEqual(recorder.lastMenuQuality, 64)
    }

    func testDanmakuUsesTopRowAndFooterFillsWidthForEveryAspectRatio() {
        for width: CGFloat in [288, 361, 788] {
            for height: CGFloat in [96, 130, 152, 210, 320, 820] {
                for fullscreen in [false, true] {
                    let bounds = CGRect(x: 16, y: 6, width: width, height: height)
                    let layout = PlayerChromeLayout(bounds: bounds, isFullScreen: fullscreen,
                        hasVideoQuality: true, hasAudioQuality: true, hasDanmaku: true,
                        videoQualityWidth: 140, audioQualityWidth: 100)
                    XCTAssertEqual(layout.audioQuality.midY, layout.danmaku.midY)
                    XCTAssertEqual(layout.danmaku.midY, layout.more.midY)
                    XCTAssertLessThan(layout.audioQuality.maxX, layout.danmaku.minX)
                    XCTAssertLessThan(layout.danmaku.maxX, layout.more.minX)
                    XCTAssertEqual(layout.timeline.minX, bounds.minX)
                    XCTAssertEqual(layout.timeline.maxX + 6, layout.fullScreen.minX)
                    XCTAssertEqual(layout.fullScreen.maxX, bounds.maxX)
                    XCTAssertEqual(layout.timeline.midY, layout.fullScreen.midY)
                    XCTAssertTrue(layout.secondaryActions.isEmpty)
                    XCTAssertGreaterThanOrEqual(layout.videoQuality.width, 48)
                    XCTAssertLessThan(layout.back.maxX, layout.videoQuality.minX)
                }
            }
        }
    }

    func testQualityPillsUseTheirOwnMeasuredWidthAndKeepMinimumHitArea() {
        let bounds = CGRect(x: 28, y: 12, width: 818, height: 361)
        let short = PlayerChromeLayout(bounds: bounds, isFullScreen: true,
                                      hasVideoQuality: true, hasAudioQuality: true,
                                      videoQualityWidth: 38, audioQualityWidth: 58)
        XCTAssertEqual(short.videoQuality.width, 48)
        XCTAssertEqual(short.audioQuality.width, 58)
        let long = PlayerChromeLayout(bounds: bounds, isFullScreen: true,
                                     hasVideoQuality: true, hasAudioQuality: true,
                                     videoQualityWidth: 104, audioQualityWidth: 96)
        XCTAssertEqual(long.videoQuality.width, 104)
        XCTAssertEqual(long.audioQuality.width, 96)
        let narrow = PlayerChromeLayout(bounds: CGRect(x: 16, y: 6, width: 288, height: 210),
                                       hasVideoQuality: true, hasAudioQuality: true,
                                       videoQualityWidth: 180, audioQualityWidth: 130)
        XCTAssertGreaterThanOrEqual(narrow.audioQuality.width, 48)
        XCTAssertGreaterThan(narrow.videoQuality.width, narrow.audioQuality.width)
        XCTAssertLessThan(narrow.back.maxX, narrow.videoQuality.minX)
        XCTAssertLessThan(narrow.audioQuality.maxX, narrow.more.minX)
    }

    func testLoadingControlsCanBeShownAndHiddenBeforeFirstFrameOnRealDevice() async throws {
        let host = try PlayerGlassSnapshotHost(ignoresSystemSafeArea: true)
        defer { host.close() }
        try await host.show(Color.black)
        let state = PlayerLoadingVisibilityFixtureState()
        let account = AccountStore(monitorNetwork: false)
        let model = PlayerViewModel(bvid: "BVLoadingControlsFixture", cid: 1,
                                    playbackURLLoader: { _, _ in throw URLError(.notConnectedToInternet) },
                                    watchProgressReporter: { _, _, _ in })
        defer { model.stop() }
        let binding = Binding(get: { state.visible }, set: { state.visible = $0 })
        let size = host.window.bounds.size
        let insets = host.window.safeAreaInsets
        try await host.show(
            PlayerGlassFixtureBackdrop()
                .overlay {
                    PlayerControlsOverlay(viewModel: model, controlsVisible: binding,
                                          isFullScreen: true, onToggleFullScreen: {},
                                          controlsSafeAreaInsets: EdgeInsets(top: insets.top, leading: insets.left,
                                                                            bottom: insets.bottom, trailing: insets.right))
                }
                .frame(width: size.width, height: size.height)
                .ignoresSafeArea()
                .environment(account).environment(ActionFeedback())
        )
        for (name, visible) in [("loading-initial-hidden", false), ("loading-manually-shown", true),
                                ("loading-manually-hidden", false)] {
            state.visible = visible
            try await Task.sleep(for: .milliseconds(120))
            host.window.layoutIfNeeded()
            XCTAssertTrue(model.isLoading)
            XCTAssertFalse(model.hasRenderedFirstFrame)
            attachSnapshot(name, from: host)
        }
    }

    func testVisibleControlRegionsRemainInsideBoundsAndDoNotOverlap() {
        for width: CGFloat in [288, 361, 788] {
            for height: CGFloat in [48, 75, 80, 95, 96, 130, 151, 152, 157, 175, 176, 210, 319, 320, 380, 510, 820] {
                for scale: CGFloat in [1, 1.3, 1.5] {
                    for isFullScreen in [false, true] {
                        for (video, audio) in [(false, false), (true, false), (false, true), (true, true)] {
                            let bounds = CGRect(x: 16, y: 6, width: width, height: height)
                            let layout = PlayerChromeLayout(bounds: bounds, textScale: scale, isFullScreen: isFullScreen,
                                                            hasVideoQuality: video, hasAudioQuality: audio)
                            let regions = [layout.back, layout.more, layout.transport, layout.timeline, layout.fullScreen,
                                           layout.metadata, layout.secondaryActions, layout.videoQuality, layout.audioQuality]
                                .filter { !$0.isEmpty }
                            let label = "\(width) × \(height), text scale \(scale), full=\(isFullScreen), qualities=\(video)/\(audio)"
                            for (index, region) in regions.enumerated() {
                                XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(region), label)
                                XCTAssertGreaterThanOrEqual(region.width, 48, label)
                                XCTAssertGreaterThanOrEqual(region.height, 48, label)
                                for other in regions.dropFirst(index + 1) {
                                    let intersection = region.intersection(other)
                                    XCTAssertTrue(intersection.isNull || intersection.width <= 0 || intersection.height <= 0,
                                                  "Control regions overlap at \(label)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testPlaybackStaysCenteredAndFullScreenStaysAtTheLowerTrailingCorner() {
        for width: CGFloat in [288, 361, 788] {
            for height: CGFloat in [48, 75, 96, 130, 151, 152, 157, 175, 176, 212, 320, 560, 820] {
                let bounds = CGRect(x: 16, y: 6, width: width, height: height)
                let layout = PlayerChromeLayout(bounds: bounds)
                if !layout.transport.isEmpty {
                    XCTAssertEqual(layout.transport.midX, bounds.midX, accuracy: 0.001)
                    XCTAssertEqual(layout.transport.midY, bounds.midY, accuracy: 0.001)
                }
                if !layout.back.isEmpty { XCTAssertEqual(layout.back.minX, bounds.minX, accuracy: 0.001) }
                XCTAssertEqual(layout.fullScreen.maxX, bounds.maxX, accuracy: 0.001)
                if layout.mode == .minimal {
                    XCTAssertTrue(layout.transport.isEmpty)
                    XCTAssertTrue(layout.more.isEmpty)
                } else {
                    XCTAssertEqual(layout.back.minY, bounds.minY, accuracy: 0.001)
                    XCTAssertEqual(layout.more.minY, bounds.minY, accuracy: 0.001)
                    XCTAssertEqual(layout.more.maxX, bounds.maxX, accuracy: 0.001)
                    XCTAssertEqual(layout.fullScreen.maxY, bounds.maxY, accuracy: 0.001)
                }
            }
        }
    }

    func testStandardVideoKeepsQualityMenusAtTopAndFullScreenAtBottom() {
        let bounds = CGRect(x: 16, y: 6, width: 361, height: 393 / (16.0 / 9) - 14)
        let layout = PlayerChromeLayout(bounds: bounds, hasVideoQuality: true, hasAudioQuality: true)
        XCTAssertEqual(layout.mode, .inline)
        XCTAssertTrue(layout.metadata.isEmpty)
        XCTAssertTrue(layout.secondaryActions.isEmpty)
        XCTAssertEqual(layout.timeline.midY, layout.fullScreen.midY)
        XCTAssertLessThan(layout.timeline.maxX, layout.fullScreen.minX)
        XCTAssertLessThan(layout.more.maxY, layout.fullScreen.minY)
        XCTAssertEqual(layout.videoQuality.minY, bounds.minY)
        XCTAssertEqual(layout.audioQuality.minY, bounds.minY)
        XCTAssertLessThan(layout.back.maxX, layout.videoQuality.minX)
        XCTAssertLessThan(layout.videoQuality.maxX, layout.audioQuality.minX)
        XCTAssertLessThan(layout.audioQuality.maxX, layout.more.minX)
        XCTAssertTrue(layout.showsTimeLabels)
    }

    func testFullscreenFooterIsOneRowWithoutSecondaryActions() {
        for width: CGFloat in [288, 361, 788] {
            for height: CGFloat in [48, 75, 96, 152, 210, 320, 380, 820] {
                let layout = PlayerChromeLayout(bounds: CGRect(x: 28, y: 12, width: width, height: height),
                                                isFullScreen: true, hasVideoQuality: true, hasAudioQuality: true)
                XCTAssertTrue(layout.secondaryActions.isEmpty)
                XCTAssertEqual(layout.timeline.midY, layout.fullScreen.midY)
                XCTAssertEqual(layout.timeline.height, 48)
                XCTAssertEqual(layout.fullScreen.height, 48)
                XCTAssertLessThan(layout.timeline.maxX, layout.fullScreen.minX)
            }
        }
    }

    func testQualityMenusYieldToMoreOnShortFramesAndToTheTitleOnlyWhenSpaceAllows() {
        for height: CGFloat in [48, 75, 95] {
            let layout = PlayerChromeLayout(bounds: CGRect(x: 16, y: 6, width: 361, height: height),
                                            hasVideoQuality: true, hasAudioQuality: true)
            XCTAssertTrue(layout.videoQuality.isEmpty)
            XCTAssertTrue(layout.audioQuality.isEmpty)
        }
        let portrait = PlayerChromeLayout(bounds: CGRect(x: 16, y: 68, width: 370, height: 764),
                                           isFullScreen: true, hasVideoQuality: true, hasAudioQuality: true)
        XCTAssertFalse(portrait.videoQuality.isEmpty)
        XCTAssertFalse(portrait.audioQuality.isEmpty)
        XCTAssertTrue(portrait.metadata.isEmpty, "Portrait prioritizes the two usable quality menus")
        let landscape = PlayerChromeLayout(bounds: CGRect(x: 28, y: 12, width: 818, height: 361),
                                            isFullScreen: true, hasVideoQuality: true, hasAudioQuality: true)
        XCTAssertGreaterThanOrEqual(landscape.metadata.width, 120)
        XCTAssertLessThan(landscape.metadata.maxX, landscape.videoQuality.minX)
    }

    func testGlassChromeAcrossRealDeviceOrientationsSizesAndLoadingStates() async throws {
        let host = try PlayerGlassSnapshotHost(ignoresSystemSafeArea: true)
        defer { host.close() }
        let cases: [(String, Bool, Double?, PlayerGlassFixtureState, Bool)] = [
            ("portrait-fullscreen", false, nil, .playing, false),
            ("landscape-fullscreen", true, nil, .playing, false),
            ("inline-portrait", false, 9.0 / 16, .playing, false),
            ("inline-square", false, 1, .playing, false),
            ("inline-16x9", false, 16.0 / 9, .playing, false),
            ("inline-21x9", false, 21.0 / 9, .playing, false),
            ("inline-ultrawide", false, 4.5, .playing, false),
            ("inline-loading", false, 16.0 / 9, .loading, false),
            ("inline-ultrawide-loading", false, 4.5, .loading, false),
            ("inline-error", false, 16.0 / 9, .error, false),
            ("live-inline", false, 16.0 / 9, .playing, true),
            ("live-landscape", true, nil, .playing, true)
        ]
        for (name, landscape, inlineRatio, state, isLive) in cases {
            // Rotate before reading UIKit safe-area insets for the fixture.
            try await host.show(Color.black, landscape: landscape)
            let insets = host.window.safeAreaInsets
            let safeArea = EdgeInsets(top: insets.top, leading: insets.left,
                                      bottom: insets.bottom, trailing: insets.right)
            try await host.show(PlayerGlassScreenFixture(size: host.window.bounds.size,
                                                          safeAreaInsets: safeArea,
                                                          inlineRatio: inlineRatio, state: state, isLive: isLive,
                                                          frameRecorder: host.frameRecorder),
                                landscape: landscape)
            XCTAssertEqual(host.window.bounds.width > host.window.bounds.height, landscape, name)
            let expectedChrome = CGRect(x: 0, y: inlineRatio == nil ? 0 : insets.top,
                                        width: host.window.bounds.width,
                                        height: inlineRatio.map { InlineVideoLayout.height(for: host.window.bounds.size, aspectRatio: $0) }
                                            ?? host.window.bounds.height)
            let actualChrome = try XCTUnwrap(host.frameRecorder.frames["chrome"], "Missing actual UIKit chrome frame")
            XCTAssertEqual(actualChrome.minX, expectedChrome.minX, accuracy: 0.5, name)
            XCTAssertEqual(actualChrome.minY, expectedChrome.minY, accuracy: 0.5, name)
            XCTAssertEqual(actualChrome.width, expectedChrome.width, accuracy: 0.5, name)
            XCTAssertEqual(actualChrome.height, expectedChrome.height, accuracy: 0.5, name)
            let coordinates = XCTAttachment(string: "window=\(host.window.bounds)\nwindow.safeArea=\(host.window.safeAreaInsets)\nhost.view.frame=\(host.controller.view.frame)\nhost.safeArea=\(host.controller.view.safeAreaInsets)\nfixture.windowFrame=\(String(describing: host.frameRecorder.frames["fixture"]))\nchrome.windowFrame=\(actualChrome)\nexpected.chrome=\(expectedChrome)")
            coordinates.name = "player-glass-\(name)-geometry"
            coordinates.lifetime = .keepAlways
            add(coordinates)
            attachSnapshot(name, from: host)
        }
    }

    func testMiniPlayerGlassSizingVariantsOnRealDevice() async throws {
        let host = try PlayerGlassSnapshotHost(ignoresSystemSafeArea: true)
        defer { host.close() }
        // The previous fixture may have left a landscape scene transition in
        // flight. Read geometry only after this window and its host settle.
        try await host.show(Color.black)
        let size = host.window.bounds.size
        let insets = host.window.safeAreaInsets
        try await host.show(
                VStack(spacing: 24) {
                    Text("小窗控件 · 三种真实画幅")
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(alignment: .top, spacing: 16) {
                        miniSpecimen(width: 144, height: 81, name: "mini-wide", recorder: host.frameRecorder)
                        miniSpecimen(width: 157.5, height: 280, name: "mini-portrait", recorder: host.frameRecorder)
                    }
                    miniSpecimen(width: 220, height: 124, name: "mini-large", recorder: host.frameRecorder)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(PlayerGlassFrameProbe(name: "mini-fixture", recorder: host.frameRecorder))
                .background(Color(white: 0.08))
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
                .environment(\.dynamicTypeSize, .large)
        )
        XCTAssertLessThan(host.window.bounds.width, host.window.bounds.height)
        let rootFrame = host.controller.view.convert(host.controller.view.bounds, to: host.window)
        assertEqualFrames(rootFrame, host.window.bounds, "The hosting view must fill the portrait window")
        let canvasFrame = try XCTUnwrap(host.frameRecorder.frames["mini-fixture"])
        assertEqualFrames(canvasFrame, host.window.bounds, "The mini fixture must fill the portrait window")
        let safeBounds = host.window.bounds.inset(by: host.window.safeAreaInsets).insetBy(dx: 16, dy: 16)
        let specimens: [(String, CGSize)] = [
            ("mini-wide", CGSize(width: 144, height: 81)),
            ("mini-portrait", CGSize(width: 157.5, height: 280)),
            ("mini-large", CGSize(width: 220, height: 124))
        ]
        var frames: [CGRect] = []
        for (name, expectedSize) in specimens {
            let frame = try XCTUnwrap(host.frameRecorder.frames[name], "Missing UIKit frame for \(name)")
            XCTAssertEqual(frame.width, expectedSize.width, accuracy: 0.5, name)
            XCTAssertEqual(frame.height, expectedSize.height, accuracy: 0.5, name)
            XCTAssertTrue(safeBounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                          "\(name) is clipped: \(frame), available: \(safeBounds)")
            for other in frames {
                XCTAssertFalse(frame.intersects(other), "Mini fixtures must not overlap")
            }
            frames.append(frame)
        }
        let geometry = XCTAttachment(string: "window=\(host.window.bounds)\nscene=\(String(describing: host.window.windowScene?.interfaceOrientation))\nhost=\(rootFrame)\ncanvas=\(canvasFrame)\nsafe=\(safeBounds)\nspecimens=\(host.frameRecorder.frames)")
        geometry.name = "player-glass-mini-size-variants-geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        attachSnapshot("mini-size-variants", from: host)
    }

    func testFullscreenQualityMenusUseTheBlackSidebarsOnRealDevice() async throws {
        let host = try PlayerGlassSnapshotHost(ignoresSystemSafeArea: true)
        defer { host.close() }
        for (name, landscape, ratio, longLabels) in [
            ("fullscreen-blackbars-16x9", true, 16.0 / 9, false),
            ("fullscreen-blackbars-4x3-long-quality", true, 4.0 / 3, true),
            ("fullscreen-portrait-long-quality", false, 9.0 / 16, true)
        ] {
            try await host.show(Color.black, landscape: landscape)
            let size = host.window.bounds.size
            let insets = host.window.safeAreaInsets
            let safe = EdgeInsets(top: insets.top, leading: insets.left,
                                  bottom: insets.bottom, trailing: insets.right)
            try await host.show(PlayerGlassScreenFixture(size: size, safeAreaInsets: safe,
                                                          inlineRatio: nil, state: .playing, isLive: false,
                                                          frameRecorder: host.frameRecorder,
                                                          fittedAspectRatio: ratio, usesLongQualityLabels: longLabels),
                                landscape: landscape)
            let chromeFrame = try XCTUnwrap(host.frameRecorder.frames["chrome"])
            let pictureFrame = try XCTUnwrap(host.frameRecorder.frames["fitted-video"])
            assertEqualFrames(chromeFrame, host.window.bounds, "Chrome must include the video's black sidebars")
            XCTAssertTrue(chromeFrame.insetBy(dx: -0.5, dy: -0.5).contains(pictureFrame))
            XCTAssertEqual(pictureFrame.width / pictureFrame.height, ratio, accuracy: 0.001)
            XCTAssertEqual(pictureFrame.midX, chromeFrame.midX, accuracy: 0.5)
            XCTAssertEqual(pictureFrame.midY, chromeFrame.midY, accuracy: 0.5)

            // These are declared layout regions anchored to a separately
            // measured full-window canvas, not a synthesized touch test.
            let sideInset: CGFloat = landscape ? 28 : insets.left + 16
            let trailingInset: CGFloat = landscape ? 28 : insets.right + 16
            let top = landscape ? max(12, insets.top + 6) : insets.top + 6
            let bounds = CGRect(x: sideInset, y: top,
                                width: size.width - sideInset - trailingInset,
                                height: size.height - top - insets.bottom - 8)
            let layout = PlayerChromeLayout(bounds: bounds, isFullScreen: true,
                                            hasVideoQuality: true, hasAudioQuality: true)
            XCTAssertEqual(layout.back.height, 48)
            XCTAssertEqual(layout.more.height, 48)
            XCTAssertEqual(layout.fullScreen.height, 48)
            XCTAssertEqual(layout.videoQuality.height, 48)
            XCTAssertEqual(layout.audioQuality.height, 48)
            XCTAssertEqual(layout.timeline.midY, layout.fullScreen.midY)
            XCTAssertTrue(layout.secondaryActions.isEmpty)
            if landscape {
                XCTAssertGreaterThan(pictureFrame.minX, chromeFrame.minX)
                XCTAssertLessThan(pictureFrame.maxX, chromeFrame.maxX)
                XCTAssertLessThanOrEqual(layout.back.maxX, pictureFrame.minX + 0.5,
                                         "Back should use the left black sidebar")
                XCTAssertGreaterThanOrEqual(layout.more.minX, pictureFrame.maxX - 0.5,
                                            "More should use the right black sidebar")
                XCTAssertGreaterThanOrEqual(layout.fullScreen.minX, pictureFrame.maxX - 0.5,
                                            "Full screen should use the right black sidebar")
                XCTAssertEqual(layout.back.minX, 28)
                XCTAssertEqual(layout.more.maxX, size.width - 28)
            }
            let geometry = XCTAttachment(string: "window=\(host.window.bounds)\nsafe=\(insets)\nchrome.actual=\(chromeFrame)\nvideo.actual=\(pictureFrame)\nlayout.back=\(layout.back)\nlayout.more=\(layout.more)\nlayout.fullscreen=\(layout.fullScreen)\nlayout.videoQuality=\(layout.videoQuality)\nlayout.audioQuality=\(layout.audioQuality)")
            geometry.name = "player-glass-\(name)-geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
            attachSnapshot(name, from: host)
        }
    }

    private func miniSpecimen(width: CGFloat, height: CGFloat, name: String,
                              recorder: PlayerGlassFrameRecorder) -> some View {
        VStack(spacing: 8) {
            Text(String(format: "%g × %g", Double(width), Double(height)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            PlayerGlassFixtureBackdrop()
                .overlay {
                    MiniPlayerControls(isPlaying: true, canControlPlayback: true,
                                       onExpand: {}, onTogglePlayback: {}, onClose: {})
                }
                .frame(width: width, height: height)
                .background(PlayerGlassFrameProbe(name: name, recorder: recorder))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func assertEqualFrames(_ actual: CGRect, _ expected: CGRect, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, message, file: file, line: line)
    }

    private func attachSnapshot(_ name: String, from host: PlayerGlassSnapshotHost) {
        let screenshot = UIGraphicsImageRenderer(bounds: host.window.bounds).image { _ in
            host.window.drawHierarchy(in: host.window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "player-glass-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor @Observable
private final class PlayerLoadingVisibilityFixtureState {
    var visible = false
}

private enum PlayerGlassFixtureState { case playing, loading, error }

private struct PlayerGlassScreenFixture: View {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    let inlineRatio: Double?
    let state: PlayerGlassFixtureState
    let isLive: Bool
    let frameRecorder: PlayerGlassFrameRecorder
    var fittedAspectRatio: Double?
    var usesLongQualityLabels = false

    var body: some View {
        Group {
            if let inlineRatio {
                VStack(spacing: 0) {
                    Color.black.frame(height: safeAreaInsets.top)
                    stage(fullScreen: false)
                        .frame(width: size.width, height: InlineVideoLayout.height(for: size, aspectRatio: inlineRatio))
                    // Comments scroll in the app. Their content must not impose
                    // an intrinsic minimum height on the outer player VStack,
                    // especially when a portrait stage uses 65% of the screen.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("海边的日落 · 一起去看世界").font(.headline)
                            HStack(spacing: 24) {
                                Text("简介").foregroundStyle(.secondary)
                                Text("评论 128").fontWeight(.semibold)
                            }
                            Divider()
                            ForEach(0..<3) { index in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle().fill(.white.opacity(0.12)).frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("评论区内容 \(index + 1)").font(.caption).foregroundStyle(.secondary)
                                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12))
                                            .frame(width: size.width * 0.6, height: 7)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.08))
                }
            } else {
                stage(fullScreen: true)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(PlayerGlassFrameProbe(name: "fixture", recorder: frameRecorder))
        .background(.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .large)
    }

    private func stage(fullScreen: Bool) -> some View {
        ZStack {
            if let fittedAspectRatio {
                GeometryReader { geometry in
                    let width = min(geometry.size.width, geometry.size.height * fittedAspectRatio)
                    ZStack {
                        Color.black
                        PlayerGlassFixtureBackdrop()
                            .frame(width: width, height: width / fittedAspectRatio)
                            .background(PlayerGlassFrameProbe(name: "fitted-video", recorder: frameRecorder))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else { PlayerGlassFixtureBackdrop() }
            if state == .error {
                ContentUnavailableView {
                    Label("无法播放", systemImage: "play.slash")
                } description: {
                    Text("网络连接已中断")
                } actions: {
                    Button("重试播放") {}
                }
                .foregroundStyle(.white)
            }
            PlayerGlassChrome(title: "海边的日落 · 一起去看世界", subtitle: "NeoBili · 1080P",
                              shareURL: URL(string: "https://example.invalid/static-player-fixture"),
                              videoQualityControl: videoQualityControl,
                              audioQualityControl: isLive ? nil : audioQualityControl,
                              position: 37, duration: 184, buffered: 92,
                              isPlaying: true, canControlPlayback: state == .playing,
                              isWaiting: state == .loading, isLive: isLive,
                              isFullScreen: fullScreen, hasError: state == .error,
                              safeAreaInsets: fullScreen ? safeAreaInsets : EdgeInsets(),
                              isDanmakuEnabled: true, showsDanmakuToggle: true, onToggleDanmaku: {},
                              onToggleCompact: fullScreen ? nil : {}) {
                Menu("定时休眠") { Button("30 分钟") {} }
            }
            .background(PlayerGlassFrameProbe(name: "chrome", recorder: frameRecorder))
        }
        .clipped()
    }

    private var videoQualityControl: PlayerQualityControl {
        PlayerQualityControl(title: usesLongQualityLabels ? "1080P 高码率" : "1080P",
                             accessibilityLabel: "分辨率",
                             options: [.init(id: 80, title: "1080P"), .init(id: 112, title: "1080P 高码率")],
                             selectedID: usesLongQualityLabels ? 112 : 80,
                             isEnabled: state == .playing, onSelect: { _ in })
    }

    private var audioQualityControl: PlayerQualityControl {
        PlayerQualityControl(title: usesLongQualityLabels ? "Hi-Res 无损" : "192K",
                             accessibilityLabel: "音质",
                             options: [.init(id: 30280, title: "192K"), .init(id: 30251, title: "Hi-Res 无损")],
                             selectedID: usesLongQualityLabels ? 30251 : 30280,
                             isEnabled: state == .playing, onSelect: { _ in })
    }
}

/// One window persists across the portrait/landscape cases. Actual scene
/// rotation is awaited before taking a screenshot; a fake wide frame inside a
/// portrait window would clip the controls and would not exercise safe areas.
@MainActor
private final class PlayerGlassSnapshotHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    let frameRecorder = PlayerGlassFrameRecorder()
    private let previousKeyWindow: UIWindow?
    private let previousOrientation: UIInterfaceOrientationMask

    init(ignoresSystemSafeArea: Bool = false) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
        previousKeyWindow = scene.keyWindow
        previousOrientation = OrientationLock.shared.supportedOrientations
        controller = UIHostingController(rootView: AnyView(Color.black))
        // The fixture already lays out a full-window canvas and explicitly
        // passes physical window insets to Chrome. Disable Hosting's separate
        // safe-area proposal so the landscape canvas isn't centered in the
        // shorter region above the 21pt home-indicator inset.
        if ignoresSystemSafeArea { controller.safeAreaRegions = [] }
        window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.makeKeyAndVisible()
    }

    func show<Content: View>(_ content: Content, landscape: Bool = false) async throws {
        frameRecorder.frames.removeAll()
        controller.rootView = AnyView(content)
        if landscape { OrientationController.enterLandscape() }
        else { OrientationController.enterPortrait() }
        guard let scene = window.windowScene else { throw URLError(.cannotFindHost) }
        var matchedOrientation = false
        for _ in 0..<100 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let size = window.bounds.size
            if size.width > 0, size.height > 0, (size.width > size.height) == landscape,
               scene.interfaceOrientation != .unknown, scene.interfaceOrientation.isLandscape == landscape {
                matchedOrientation = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard matchedOrientation else { throw URLError(.timedOut) }
        if let transition = controller.transitionCoordinator, transition.isAnimated {
            await withCheckedContinuation { continuation in
                if !transition.animate(alongsideTransition: nil, completion: { _ in continuation.resume() }) {
                    continuation.resume()
                }
            }
        }
        // A new UIWindow can acquire portrait bounds while its hosting root
        // still has the outgoing landscape size. Reset this test-owned root
        // after rotation, instead of assuming window.bounds proves layout.
        window.frame = scene.coordinateSpace.bounds
        controller.view.frame = window.bounds
        window.setNeedsLayout()
        controller.view.setNeedsLayout()
        // Give the real hosting/glass compositor time to commit its new content.
        try await Task.sleep(for: .milliseconds(100))
        var stableSamples = 0
        for _ in 0..<100 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let rootFrame = controller.view.convert(controller.view.bounds, to: window)
            let windowBounds = window.bounds
            let sceneSize = scene.coordinateSpace.bounds.size
            let aligned = abs(rootFrame.minX - windowBounds.minX) < 0.5
                && abs(rootFrame.minY - windowBounds.minY) < 0.5
                && abs(rootFrame.width - windowBounds.width) < 0.5
                && abs(rootFrame.height - windowBounds.height) < 0.5
                && abs(windowBounds.width - sceneSize.width) < 0.5
                && abs(windowBounds.height - sceneSize.height) < 0.5
            let oriented = scene.interfaceOrientation.isLandscape == landscape
                && (windowBounds.width > windowBounds.height) == landscape
            stableSamples = aligned && oriented ? stableSamples + 1 : 0
            if stableSamples == 3 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Snapshot host did not settle: window=\(window.bounds), root=\(controller.view.frame), scene=\(scene.coordinateSpace.bounds), orientation=\(scene.interfaceOrientation)")
        throw URLError(.timedOut)
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        OrientationLock.shared.supportedOrientations = previousOrientation
        previousKeyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: previousOrientation)) { _ in }
    }
}

/// Local colors provide visible detail behind translucent glass without
/// downloading a video or embedding an image asset in the test bundle.
private struct PlayerGlassFixtureBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.18, blue: 0.35),
                                        Color(red: 0.36, green: 0.46, blue: 0.48),
                                        Color(red: 0.78, green: 0.55, blue: 0.3)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.25))
                    .frame(width: geometry.size.width * 0.65)
                    .offset(x: geometry.size.width * 0.25, y: -geometry.size.height * 0.18)
                Rectangle().fill(.black.opacity(0.2))
                    .frame(height: geometry.size.height * 0.18)
                    .rotationEffect(.degrees(-18))
                    .offset(y: geometry.size.height * 0.18)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}


/// Records the actual UIKit placement in UIWindow coordinates, independently
/// of SwiftUI's logical/global coordinate space and PlayerChromeLayout math.
@MainActor
private final class PlayerGlassFrameRecorder {
    var frames: [String: CGRect] = [:]
}

private struct PlayerGlassFrameProbe: UIViewRepresentable {
    let name: String
    let recorder: PlayerGlassFrameRecorder

    func makeUIView(context: Context) -> PlayerGlassProbeView {
        let view = PlayerGlassProbeView()
        view.isUserInteractionEnabled = false
        view.capture = { [weak recorder, name] frame in recorder?.frames[name] = frame }
        return view
    }

    func updateUIView(_ view: PlayerGlassProbeView, context: Context) {
        view.capture = { [weak recorder, name] frame in recorder?.frames[name] = frame }
        view.setNeedsLayout()
    }
}

private final class PlayerGlassProbeView: UIView {
    var capture: ((CGRect) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recordFrame()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        recordFrame()
    }

    private func recordFrame() {
        guard let window, bounds.width > 0, bounds.height > 0 else { return }
        capture?(convert(bounds, to: window))
    }
}

@Observable @MainActor
private final class PlayerProgressIsolationState {
    var position = 0.0
    var buffered = 0.0
    var quality = 80
}

@MainActor
private final class PlayerProgressIsolationRecorder {
    var menuBuilds = 0
    var lastPosition = -1.0
    var lastBuffered = -1.0
    var lastMenuQuality = 0
}

private struct PlayerProgressIsolationFixture: View {
    let progress: PlayerProgressIsolationState
    let recorder: PlayerProgressIsolationRecorder

    var body: some View {
        let quality = PlayerQualityControl(
            title: "Q\(progress.quality)", accessibilityLabel: "分辨率",
            options: [.init(id: 64, title: "720P"), .init(id: 80, title: "1080P")],
            selectedID: progress.quality, isEnabled: true,
            onSelect: { progress.quality = $0 }
        )
        PlayerGlassChrome(
            videoQualityControl: quality,
            progressSource: PlayerProgressSource {
                recorder.lastPosition = progress.position
                recorder.lastBuffered = progress.buffered
                return .init(position: progress.position, duration: 600, buffered: progress.buffered)
            },
            isPlaying: true
        ) {
            recordedMenu(quality: quality.selectedID)
        }
        .frame(height: 230)
    }

    private func recordedMenu(quality: Int) -> some View {
        recorder.menuBuilds += 1
        recorder.lastMenuQuality = quality
        return Button("Probe") {}
    }
}
