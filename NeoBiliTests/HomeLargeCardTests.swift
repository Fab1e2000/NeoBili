import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class HomeLargeCardTests: XCTestCase {
    private func video(_ id: Int, large: Bool = false) -> VideoSummary {
        var v = VideoSummary(bvid: "fixture-\(id)",aid:id,cid:id,title:large ? "抹茶冰淇淋选购指南" : "普通推荐视频 \(id)",
            pic:"",desc:"",duration:241,pubdate:0,owner:.init(mid:1,name:"测试 UP 主",face:""),
            stat:.init(view:109000,danmaku:118,like:4598,favorite:0,coin:0,share:0,reply:0))
        v.isLargeRecommendationCard = large
        v.recommendationBadge = "4万点赞"
        v.playbackEntry = .recommendation(trackID:"fixture-track",reportFlowData:nil)
        return v
    }

    func testLargeTitleIsSingleLineAndBadgeSurvivesCardReuse() {
        let card = NativeHomeVideoCard.CardView(resolveAvatar: { _ in nil })
        card.frame = CGRect(x: 0, y: 0, width: 386, height: 278)
        for large in [true, false, true] {
            card.configure(video: video(1, large: large), titleWidth: 370, dynamicTypeSize: .large, scale: 3,
                           aspectRatio: large ? HomeCardLayout.largeCoverAspectRatio : HomeCardLayout.coverAspectRatio)
            card.layoutIfNeeded()
            let title = card.subviews.first { $0.accessibilityIdentifier == "home.card.title" } as? UILabel
            let badge = card.subviews.first { $0.accessibilityIdentifier == "home.recommendation.badge" } as? UILabel
            XCTAssertEqual(title?.numberOfLines, large ? 1 : 2)
            XCTAssertEqual(badge?.text, "4万点赞")
            XCTAssertEqual(badge?.isHidden, false)
        }
    }

    func testLargeCoverStatsPixelsDoNotMoveWhenPlaybackStarts() {
        let v = video(1, large: true)
        func render(_ playing: Bool) -> UIImage {
            let host = UIHostingController(rootView: HomeLargeCoverOverlay(video: v, isPlaying: playing))
            host.view.frame = CGRect(x: 0, y: 0, width: 386, height: 217)
            host.view.backgroundColor = .clear
            host.view.layoutIfNeeded()
            return UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in
                host.view.layer.render(in: context.cgContext)
            }
        }
        let still = render(false), playing = render(true)
        let rect = CGRect(x: 0, y: 0, width: 250 * still.scale, height: 217 * still.scale)
        let a = still.cgImage?.cropping(to: rect), b = playing.cgImage?.cropping(to: rect)
        XCTAssertNotNil(a); XCTAssertNotNil(b)
        XCTAssertEqual(a.map { UIImage(cgImage: $0).pngData() }, b.map { UIImage(cgImage: $0).pngData() })
        for (name, image) in [("cover-idle", still), ("cover-playing", playing)] {
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testMixedCardRowsKeepServerOrderAndLargeCardsAlone() {
        let items=[video(1),video(2,large:true),video(3),video(4),video(5,large:true)]
        let rows=HomeFeedRow.group(items.map(HomeFeedItem.video))
        XCTAssertEqual(HomeFeedRow.collectionItems(rows).map(\.id),items.map { HomeFeedItem.video($0).id })
        let sizes=rows.compactMap { row -> Int? in if case .videos(let v)=row {return v.count};return nil }
        XCTAssertEqual(sizes,[1,1,2,1])
    }

    func testVisibleLayoutAndScreenshotsInLightDarkAndLandscape() async throws {
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {$0 as? UIWindowScene}.first)
        let previous=scene.keyWindow
        let window=UIWindow(windowScene:scene)
        defer { window.isHidden=true;window.rootViewController=nil;previous?.makeKey() }
        let videos=[video(1,large:true),video(2),video(3),video(4,large:true),video(5)]
        let model=HomeViewModel(fetchRecommendations:{_ in .init(videos:[],nextRequest:nil)})
        let host=UIHostingController(rootView:HomeFeedCollection(rows:HomeFeedRow.group(videos.map(HomeFeedItem.video)),
            viewModel:model,hidesPortraitVideos:false,isRefreshing:false,isInteractionEnabled:true,
            refreshDistance:100,controller:HomeFeedScrollController(),onRefresh:{},onOpenLastSeen:{},pinsTitleBar:true)
            .environment(AccountStore(monitorNetwork:false)).environment(NowPlayingStore()).environment(ActionFeedback()))
        window.rootViewController=host;window.makeKeyAndVisible()
        func find(_ view:UIView)->UICollectionView? {
            if let v=view as? UICollectionView {return v}
            return view.subviews.lazy.compactMap(find).first
        }
        for (name,size,style) in [("light",CGSize(width:402,height:874),UIUserInterfaceStyle.light),
                                  ("dark",CGSize(width:402,height:874),.dark),
                                  ("landscape",CGSize(width:874,height:402),.light)] {
            window.frame=CGRect(origin:.zero,size:size);window.overrideUserInterfaceStyle=style
            host.view.frame=window.bounds;window.layoutIfNeeded()
            try await Task.sleep(for:.milliseconds(250))
            let collection=try XCTUnwrap(find(host.view));collection.collectionViewLayout.invalidateLayout();collection.layoutIfNeeded()
            let big=try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at:IndexPath(item:0,section:0)))
            let left=try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at:IndexPath(item:0,section:1)))
            let right=try XCTUnwrap(collection.collectionViewLayout.layoutAttributesForItem(at:IndexPath(item:1,section:1)))
            XCTAssertEqual(big.frame.width,collection.bounds.width-16,accuracy:1)
            XCTAssertEqual(left.frame.width,right.frame.width,accuracy:1)
            XCTAssertLessThan(left.frame.width,big.frame.width*0.6)
            XCTAssertEqual(left.frame.minY,right.frame.minY,accuracy:1)
            XCTAssertGreaterThanOrEqual(left.frame.minY,big.frame.maxY)
            let image=UIGraphicsImageRenderer(bounds:window.bounds).image {_ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)}
            let attachment=XCTAttachment(image:image);attachment.name="home-large-card-\(name)";attachment.lifetime = .keepAlways;add(attachment)
            let path=FileManager.default.temporaryDirectory.appendingPathComponent("home-large-card-\(name).png")
            try image.pngData()?.write(to:path)
        }
    }

    func testSilentPreviewDoesNotAcquireAudioOutputAndUsesInlineWatchSource() {
        var config=VideoPlaybackConfiguration.fastStart;config.silentPreview=true
        let options=Dictionary(uniqueKeysWithValues:MPVPlaybackOptions.make(configuration:config,isSimulator:true,httpHeaderFields:""))
        XCTAssertEqual(options["mute"],"yes");XCTAssertEqual(options["ao"],"null")
        XCTAssertNil(Dictionary(uniqueKeysWithValues:MPVPlaybackOptions.make(configuration:.fastStart,isSimulator:true,httpHeaderFields:"")).first { $0.key=="ao" })
        let report=PlaybackWatchReport(position:151,watchedTime:140,pausedTime:0,maximumPosition:151,duration:241,
            startTimestamp:0,sourceFields:["from":"76","spmid":"tm.recommend.0.0"],isInlinePreview:true)
        XCTAssertEqual(report.mobileParameters["auto_play"],"2")
        XCTAssertEqual(report.mobileParameters["from"],"76")
        XCTAssertEqual(report.mobileParameters["played_time"],"140")
        XCTAssertEqual(report.mobileParameters["last_play_progress_time"],"151")
    }

    func testLeavingCardCancelsLateManifestAndNoPlaybackIsReported() async throws {
        let gate=PreviewGate()
        let preview=HomeInlinePreview(loader:{_,_,_ in await gate.wait();return (1,.init(video:.init(primary:URL(string:"https://example.invalid/video")!,backups:[]),audio:nil,duration:241))})
        preview.select(video(1,large:true))
        try await Task.sleep(for:.milliseconds(300))
        preview.stop();await gate.release()
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertNil(preview.videoID);XCTAssertNil(preview.session)
        XCTAssertFalse(preview.hasFirstFrame)
    }

    func testSilentPreviewReportsOnlyAdvancingPlaybackAndFinishesOnce() async throws {
        var time=0.0
        let recorder=PreviewReports()
        let loaded=expectation(description:"preview manifest ready")
        let preview=HomeInlinePreview(loader:{_,_,_ in
            (1,.init(video:.init(primary:URL(string:"https://example.invalid/video")!,backups:[]),audio:nil,duration:241))
        },clock:{time},reporter:{await recorder.append($0)},opener:{_,_ in loaded.fulfill()})
        preview.select(video(1,large:true))
        await fulfillment(of:[loaded],timeout:2)
        let callback=try XCTUnwrap(preview.session?.onEvent)
        callback(.firstFrame);callback(.playing(true));callback(.position(30))
        time=1;callback(.position(31));time=2;callback(.position(32))
        preview.stop();preview.stop();callback(.position(40))
        let values=await recorder.waitForFinish()
        XCTAssertEqual(values.map(\.delivery),[.start,.finish])
        XCTAssertEqual(values.last?.watchedTime,2)
        XCTAssertEqual(values.last?.position,32)
        XCTAssertTrue(values.allSatisfy(\.isInlinePreview))
        XCTAssertEqual(values.last?.sourceFields["from"],"76")
        XCTAssertEqual(values.first?.playbackSession,values.last?.playbackSession)
    }
}

private actor PreviewGate {
    var continuation:CheckedContinuation<Void,Never>?
    func wait() async {await withCheckedContinuation {continuation=$0}}
    func release() {continuation?.resume();continuation=nil}
}

private actor PreviewReports {
    var values:[PlaybackWatchReport]=[]
    func append(_ v:PlaybackWatchReport) {values.append(v)}
    func waitForFinish() async->[PlaybackWatchReport] {
        for _ in 0..<100 {if values.last?.delivery == .finish {break};try? await Task.sleep(for:.milliseconds(10))}
        return values
    }
}
