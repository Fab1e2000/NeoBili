#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class VideoNativeCanvasTests: XCTestCase {
    func testFixedCanvasKeepsScrollGeometryPagingAndPlayerTouches() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let model = CanvasFixtureState()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: NativeCanvasFixture(model: model))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        let horizontal = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first {
            $0.contentSize.width > $0.bounds.width * 1.5
        })
        let vertical = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first {
            $0.contentSize.height > 1000 && $0.contentSize.width < $0.bounds.width + 1
        })
        let size = vertical.bounds.size
        let origin = vertical.convert(vertical.bounds.origin, to: window)
        XCTAssertEqual(model.firstTop[.description] ?? -1, origin.y + 498, accuracy: 2)
        for distance: CGFloat in [1, 100, 333, 498, 0] {
            model.distance = distance
            try await Task.sleep(for: .milliseconds(35))
            window.layoutIfNeeded()
            XCTAssertEqual(model.firstTop[.description] ?? -1, origin.y + 498 - distance, accuracy: 2)
            XCTAssertEqual(vertical.bounds.size, size)
            XCTAssertEqual(vertical.convert(vertical.bounds.origin, to: window).y, origin.y, accuracy: 0.001)
            // A visually clipped fixed canvas must not intercept the player's touches.
            let playerBottom = host.view.safeAreaInsets.top + 554 - distance
            for y in [host.view.safeAreaInsets.top + 20, playerBottom - 12] {
                let hit = try XCTUnwrap(window.hitTest(CGPoint(x: window.bounds.midX, y: y), with: nil))
                XCTAssertFalse(hit.isDescendant(of: horizontal), "Canvas stole player tap at distance \(distance), y \(y)")
            }
            let listHit = try XCTUnwrap(window.hitTest(CGPoint(x: window.bounds.midX, y: window.bounds.maxY - 100), with: nil))
            XCTAssertTrue(listHit.isDescendant(of: horizontal), "Visible list must remain interactive")
            if distance == 0 || distance == 498 {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image)
                attachment.name = "native-canvas-\(Int(distance))"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        withAnimation(.linear(duration: 0.8)) { model.section = .comments }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(horizontal.contentOffset.x, 1)
        XCTAssertLessThan(horizontal.contentOffset.x, horizontal.bounds.width - 1)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(horizontal.contentOffset.x, horizontal.bounds.width, accuracy: 1)
        model.errorHeight = 96
        model.loadingComments = true
        try await Task.sleep(for: .milliseconds(100))
        let loading = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first {
            $0.contentSize.height > 400 && $0.contentSize.height < 1500
                && $0.contentSize.width < $0.bounds.width + 1
        })
        let loadingSize = loading.bounds.size
        for distance: CGFloat in [498, 0, 333] {
            model.distance = distance
            try await Task.sleep(for: .milliseconds(35))
            window.layoutIfNeeded()
            XCTAssertEqual(loading.bounds.size, loadingSize)
            let playerBottom = host.view.safeAreaInsets.top + 554 - distance
            let hit = try XCTUnwrap(window.hitTest(CGPoint(x: window.bounds.midX, y: playerBottom - 12), with: nil))
            XCTAssertFalse(hit.isDescendant(of: horizontal), "Loading page stole player touch")
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "native-canvas-loading-with-error"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testProductionCommentsKeepTheirTopVisible() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let model = CanvasFixtureState()
        model.section = .comments
        let comments = try (1...60).map { id in
            try JSONDecoder().decode(Comment.self, from: Data("""
            {"rpid":\(id),"ctime":1,"like":0,"rcount":0,"member":{"uname":"测试\(id)","avatar":""},"content":{"message":"评论顶部测试 \(id)"}}
            """.utf8))
        }
        let viewModel = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, _ in
            CommentPage(page: .init(num: 1, size: 60, count: 60), replies: comments)
        })
        await viewModel.loadInitial()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: NativeCanvasFixture(model: model, comments: viewModel)
            .environment(AccountStore()).environment(ActionFeedback()).environment(NowPlayingStore())
            .environment(\.colorScheme, .light))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(300))
        window.layoutIfNeeded()
        let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first {
            $0.contentSize.height > 1000 && $0.contentSize.width < $0.bounds.width + 1
        })
        let canvasOrigin = scroll.convert(scroll.bounds.origin, to: window).y
        for distance: CGFloat in [0, 498, 333, 0] {
            model.distance = distance
            try await Task.sleep(for: .milliseconds(100))
            window.layoutIfNeeded()
            // External collapse/resume must preserve the first comment, and returning
            // from a reading offset must reveal it at the visible viewport's top.
            XCTAssertEqual(scroll.contentOffset.y, distance, accuracy: 1)
            scroll.setContentOffset(CGPoint(x: 0, y: distance + 900), animated: false)
            scroll.setContentOffset(CGPoint(x: 0, y: distance), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let region = CGRect(x: 55, y: canvasOrigin + 498 - distance + 12, width: 240, height: 50)
            XCTAssertGreaterThan(try darkPixelCount(image, in: region), 100,
                                 "First comment is geometrically at the top but not rendered at distance \(distance)")
            let attachment = XCTAttachment(image: image)
            attachment.name = "production-comments-top-\(Int(distance))"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    private func darkPixelCount(_ image: UIImage, in region: CGRect) throws -> Int {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: region.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return stride(from: 0, to: buffer.count, by: 4).reduce(0) { count, index in
                count + (buffer[index] < 120 && buffer[index + 1] < 120 && buffer[index + 2] < 120 ? 1 : 0)
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
}

@MainActor @Observable private final class CanvasFixtureState {
    var distance: CGFloat = 0
    var section = VideoPageSection.description
    var errorHeight: CGFloat = 0
    var loadingComments = false
    var firstTop: [VideoPageSection: CGFloat] = [:]
}
private struct NativeCanvasFixture: View {
    @Bindable var model: CanvasFixtureState
    var comments: CommentsViewModel? = nil
    @State private var barHeight: CGFloat = 44
    @State private var position = ScrollPosition(edge: .top)
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Color.black.overlay(Text("播放器").foregroundStyle(.white)).frame(height: 554 - model.distance)
                if model.errorHeight > 0 { Text("详情加载失败 · 重试").frame(height: model.errorHeight) }
                VStack(spacing: 0) {
                    VideoSectionBar(selection: $model.section)
                        .background(.bar)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                    VideoScrollCanvas(height: geometry.size.height - 56 - barHeight - model.errorHeight, content: pages)
                }.frame(maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 21, topTrailingRadius: 21))
            }.frame(height: geometry.size.height)
        }.background(.black)
    }
    private var pages: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                page("简介", section: .description).id(VideoPageSection.description)
                page("评论", section: .comments).id(VideoPageSection.comments)
            }.scrollTargetLayout()
        }.scrollPosition(id: Binding(get: { model.section }, set: { if let value = $0 { model.section = value } }))
            .scrollTargetBehavior(.paging).scrollIndicators(.hidden)
    }
    private func page(_ name: String, section: VideoPageSection) -> some View {
        Group {
            if section == .comments, let comments {
                CommentsView(viewModel: comments, scrollPosition: $position, collapseConsume: { _ in 0 }, canCollapse: { _ in false })
            } else if section == .comments, model.loadingComments {
                VideoCommentsLoadingView(consume: { _ in 0 }, canConsume: { _ in false })
            } else {
                ScrollView {
            LazyVStack { ForEach(0..<200) { id in
                Text("\(name) \(id) " + String(repeating: "动态高度内容 中文 English 👨‍💻 ", count: id % 4 + 1))
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                Divider()
            } }
            .overlay(alignment: .top) {
                Color.clear.frame(height: 1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { model.firstTop[section] = $0 }
            }
            .background {
                PausedVideoCollapseScroll(consume: { delta in
                    let old = model.distance
                    model.distance = min(max(0, old + delta), 498)
                    return model.distance - old
                }, end: {}, canConsume: { delta in delta > 0 ? model.distance < 498 : model.distance > 0 }, section: section)
            }
            .padding(.top, 498)
                }
                .contentMargins(.bottom, 80, for: .scrollContent)
                .scrollPosition($position)
            }
        }.environment(\.videoScrollContext, VideoScrollContext(minimumContentHeight: 500, reservation: 498,
            distance: { model.distance }, isActive: { model.section == $0 }))
            .containerRelativeFrame(.horizontal).frame(maxHeight: .infinity)
    }
}
