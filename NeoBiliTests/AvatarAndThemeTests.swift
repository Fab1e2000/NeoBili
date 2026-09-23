import XCTest
import SwiftUI
@testable import NeoBili

@MainActor
final class AvatarAndThemeTests: XCTestCase {
    func testEmptyAvatarAddressDoesNotBecomeRelativeURL() {
        XCTAssertNil(URL.biliSecure(""))
        XCTAssertNil(URL.biliSecure(" \n "))
        XCTAssertEqual(URL.biliSecure("//example.com/face.png")?.absoluteString, "https://example.com/face.png")
    }

    func testAvatarRequestsAreCoalescedCachedAndBounded() async {
        let probe = AvatarRequestProbe()
        let cache = OwnerAvatarCache { await probe.load($0) }
        await withTaskGroup(of: Void.self) { group in
            for mid in [1, 1, 2, 3, 4, 5, 6, 1] {
                group.addTask { _ = await cache.url(for: mid) }
            }
        }
        _ = await cache.url(for: 1)
        _ = await cache.url(for: 0)
        let result = await probe.snapshot()
        XCTAssertEqual(result.calls, 6)
        XCTAssertLessThanOrEqual(result.maximum, 2)
    }

    func testMissingAvatarIsFilledAndReusedCardRejectsOldOwner() async throws {
        PreparedTitle.warmUp(dynamicTypeSize: .large)
        let redURL = URL(string: "https://example.invalid/old-avatar.png")!
        let blueURL = URL(string: "https://example.invalid/new-avatar.png")!
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 16, height: 16), scale: 3))
        func bitmap(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        }
        let red = bitmap(.red), blue = bitmap(.blue)
        BiliImageMemoryCache.insert(red, for: redURL, pixelSize: pixels)
        BiliImageMemoryCache.insert(blue, for: blueURL, pixelSize: pixels)
        let card = NativeHomeVideoCard.CardView { mid in
            if mid == 1 { try? await Task.sleep(for: .milliseconds(200)) }
            return mid == 1 ? redURL : blueURL
        }
        func video(_ mid: Int) -> VideoSummary {
            .init(bvid: "BV-avatar-\(mid)", aid: mid, cid: mid, title: "测试", pic: "", desc: "", duration: 10,
                  pubdate: 0, owner: .init(mid: mid, name: "UP", face: ""),
                  stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        }
        card.frame = CGRect(x: 0, y: 0, width: 188, height: 222)
        card.configure(video: video(1), titleWidth: 172, dynamicTypeSize: .large, scale: 3)
        try await Task.sleep(for: .milliseconds(180))
        card.configure(video: video(2), titleWidth: 172, dynamicTypeSize: .large, scale: 3)
        try await Task.sleep(for: .milliseconds(400))
        card.layoutIfNeeded()
        let avatar = try XCTUnwrap(card.subviews.first { $0.accessibilityIdentifier == "home.owner.avatar" })
        XCTAssertTrue(avatar.subviews.compactMap { ($0 as? UIImageView)?.image }.contains { $0 === blue })
        XCTAssertFalse(avatar.subviews.compactMap { ($0 as? UIImageView)?.image }.contains { $0 === red })
        XCTAssertTrue(card.bounds.contains(avatar.frame))
    }

    func testHotSearchDecodingKeepsSearchKeywordSeparateFromDisplayTitle() throws {
        let json = #"{"code":0,"list":[{"keyword":"IG JDG","show_name":"IG晋级世界赛"},{"keyword":"视频","show_name":""}]}"#
        let payload = try JSONDecoder().decode(HotSearchPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.list[0].keyword, "IG JDG")
        XCTAssertEqual(payload.list[0].title, "IG晋级世界赛")
        XCTAssertEqual(payload.list[1].title, "视频")
    }

    func testSystemTintStaysNeutralWhileCustomTintUsesTheme() async throws {
        let suite = "neobili.theme-scope.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ruby", forKey: AppTheme.storageKey)
        let host = UIHostingController(rootView: VStack {
            TintProbe(tag: 901).frame(width: 20, height: 20)
            CustomThemeTintProbe().frame(width: 20, height: 20)
        }.appTheme().defaultAppStorage(defaults))
        host.overrideUserInterfaceStyle = .light
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = try XCTUnwrap(previous?.windowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(100))
        let system = try XCTUnwrap(host.view.viewWithTag(901))
        let custom = try XCTUnwrap(host.view.viewWithTag(902))
        assertSameColor(system.tintColor.resolvedColor(with: system.traitCollection), UIColor.label.resolvedColor(with: system.traitCollection))
        assertSameColor(custom.tintColor.resolvedColor(with: custom.traitCollection), UIColor(AppTheme.selected("ruby").color))
    }
}

private struct TintProbe: UIViewRepresentable {
    let tag: Int
    func makeUIView(context: Context) -> UIView { let view = UIView(); view.tag = tag; return view }
    func updateUIView(_ view: UIView, context: Context) {}
}

private actor AvatarRequestProbe {
    private var calls = 0
    private var active = 0
    private var maximum = 0
    func load(_ mid: Int) async -> URL? {
        calls += 1; active += 1; maximum = max(maximum, active)
        try? await Task.sleep(for: .milliseconds(20))
        active -= 1
        return URL(string: "https://example.invalid/\(mid).png")
    }
    func snapshot() -> (calls: Int, maximum: Int) { (calls, maximum) }
}

private func assertSameColor(_ actual: UIColor, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
    XCTAssertTrue(actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa), file: file, line: line)
    XCTAssertTrue(expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea), file: file, line: line)
    for (value, reference) in zip([ar, ag, ab, aa], [er, eg, eb, ea]) {
        XCTAssertEqual(value, reference, accuracy: 0.001, file: file, line: line)
    }
}

private struct CustomThemeTintProbe: View {
    @Environment(\.appThemeColor) private var themeColor
    var body: some View { TintProbe(tag: 902).tint(themeColor) }
}
