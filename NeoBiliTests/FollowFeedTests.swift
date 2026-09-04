import XCTest
@testable import NeoBili

/// 关注页和搜索联想都在解服务端返回的「非标准」结构：动态流的 aid 是字符串、
/// 播放量是排好版的文字，联想接口没有候选词时 result 会从对象退化成数组。
/// 这些地方一旦解错，页面就是一片空白，所以用样例数据锁住。
final class FollowFeedTests: XCTestCase {
    // MARK: - 关注动态流

    func testDynamicFeedKeepsOnlyArchiveItems() throws {
        let json = """
        {
          "has_more": true,
          "offset": "1029036563270434817",
          "items": [
            {
              "id_str": "1001",
              "type": "DYNAMIC_TYPE_AV",
              "modules": {
                "module_author": {
                  "mid": 946974,
                  "name": "影视飓风",
                  "face": "https://i0.hdslb.com/face.jpg",
                  "pub_time": "3小时前",
                  "pub_ts": 1788058800
                },
                "module_dynamic": {
                  "major": {
                    "type": "MAJOR_TYPE_ARCHIVE",
                    "archive": {
                      "aid": "117181958331993",
                      "bvid": "BV1Na4Q64Eos",
                      "title": "去了一趟西班牙",
                      "cover": "http://i0.hdslb.com/cover.jpg",
                      "duration_text": "24:34",
                      "stat": {"play": "245.8万", "danmaku": "1.2万"}
                    }
                  }
                }
              }
            },
            {
              "id_str": "1002",
              "type": "DYNAMIC_TYPE_DRAW",
              "modules": {
                "module_author": {"mid": 1, "name": "图文", "face": "", "pub_time": "昨天"},
                "module_dynamic": {"major": {"type": "MAJOR_TYPE_DRAW"}}
              }
            }
          ]
        }
        """
        let page = try JSONDecoder().decode(DynamicFeedPage.self, from: Data(json.utf8))

        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.offset, "1029036563270434817")
        XCTAssertEqual(page.items.count, 2, "两条都要解出来")

        // 第二条是既没有图也没有文字的图文动态，收敛成卡片时会被丢掉。
        let entries = page.entries
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "1001")
        XCTAssertEqual(entry.authorName, "影视飓风")
        XCTAssertEqual(entry.publishedText, "3小时前")

        let video = try XCTUnwrap(entry.video)
        XCTAssertEqual(video.bvid, "BV1Na4Q64Eos")
        XCTAssertEqual(video.aid, 117_181_958_331_993, "动态接口的 aid 是字符串，要还原成数字")
        XCTAssertEqual(video.playText, "245.8万", "播放量是服务端排好版的文字，原样显示")
        XCTAssertEqual(video.durationText, "24:34")
        XCTAssertEqual(video.secureCoverURL?.scheme, "https", "封面统一走 https")
    }

    func testTextAndImageDynamicsBecomeEntries() throws {
        let json = """
        {
          "items": [
            {
              "id_str": "4001",
              "type": "DYNAMIC_TYPE_WORD",
              "basic": {"comment_id_str": "4001", "comment_type": 17},
              "modules": {
                "module_author": {"mid": 1, "name": "写字的", "face": "", "pub_time": "1小时前"},
                "module_dynamic": {"desc": {"text": "今天也在写代码"}, "major": null},
                "module_stat": {"comment": {"count": 12}, "forward": {"count": 3},
                                "like": {"count": 45, "status": true}}
              }
            },
            {
              "id_str": "4002",
              "type": "DYNAMIC_TYPE_DRAW",
              "basic": {"comment_id_str": "4002", "comment_type": 11},
              "modules": {
                "module_author": {"mid": 2, "name": "发图的", "face": "", "pub_time": "昨天"},
                "module_dynamic": {
                  "desc": {"text": "出去玩了"},
                  "major": {"opus": {"summary": {"text": "出去玩了"},
                            "pics": [{"url": "//i0.hdslb.com/1.jpg", "width": 1200, "height": 1600},
                                     {"url": "//i0.hdslb.com/2.jpg", "width": 800, "height": 800}]}}
                },
                "module_stat": {"comment": {"count": 0}, "forward": {"count": 0}, "like": {"count": 0}}
              }
            },
            {
              "id_str": "4003",
              "type": "DYNAMIC_TYPE_FORWARD",
              "modules": {"module_author": {"mid": 3, "name": "转发的", "face": ""},
                          "module_dynamic": {"desc": {"text": "转"}}}
            }
          ]
        }
        """
        let entries = try JSONDecoder().decode(DynamicFeedPage.self, from: Data(json.utf8)).entries

        XCTAssertEqual(entries.map(\.id), ["4001", "4002"], "转发动态不进列表")

        let word = entries[0]
        XCTAssertEqual(word.text, "今天也在写代码")
        XCTAssertNil(word.video)
        XCTAssertTrue(word.images.isEmpty)
        XCTAssertEqual(word.likeCount, 45)
        XCTAssertTrue(word.isLikedByServer)
        XCTAssertEqual(word.commentCount, 12)
        XCTAssertEqual(word.forwardCount, 3)
        XCTAssertEqual(word.commentOid, 4001)
        XCTAssertEqual(word.commentType, 17, "纯文字动态的评论区类型是 17")
        XCTAssertTrue(word.hasComments)

        let draw = entries[1]
        XCTAssertEqual(draw.images.count, 2)
        XCTAssertEqual(draw.images.first?.secureURL?.absoluteString, "https://i0.hdslb.com/1.jpg")
        XCTAssertEqual(draw.commentType, 11, "图文动态的评论区类型是 11")
        XCTAssertEqual(draw.images[0].displayAspectRatio, 0.75, accuracy: 0.001, "竖图压到 3:4 为止")
    }

    func testDynamicFeedSurvivesMissingFields() throws {
        let json = """
        {"items": [{"id_str": "2001", "modules": {}}]}
        """
        let page = try JSONDecoder().decode(DynamicFeedPage.self, from: Data(json.utf8))

        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.offset, "")
        XCTAssertTrue(page.entries.isEmpty, "没有内容的动态不该进列表")
    }

    func testDynamicFeedSkipsUndecodableItemsAndAcceptsLooseTypes() throws {
        // 服务端偶尔会把 offset 回成数字、has_more 回成 0/1、播放量回成裸数字，
        // 一页里也可能混进结构完全不同的条目。任何一样都不该让整页失败。
        let json = """
        {
          "has_more": 1,
          "offset": 1029036563270434817,
          "items": [
            42,
            {"id_str": "3001", "modules": {"module_dynamic": "这里本该是对象"}},
            {"id_str": "3002",
             "modules": {"module_author": {"mid": "946974", "name": "UP", "face": "", "pub_time": "刚刚"},
                         "module_dynamic": {"major": {"archive": {"aid": 114, "bvid": "BV1ok",
                                            "title": "标题", "cover": "//i0.hdslb.com/c.jpg",
                                            "duration_text": "01:00", "stat": {"play": 12345}}}}}}
          ]
        }
        """
        let page = try JSONDecoder().decode(DynamicFeedPage.self, from: Data(json.utf8))

        XCTAssertTrue(page.hasMore, "has_more 是 1 也算 true")
        XCTAssertEqual(page.offset, "1029036563270434817", "数字游标转成字符串")

        let entries = page.entries
        XCTAssertEqual(entries.count, 1, "解不动的条目跳过，能解的照常返回")
        XCTAssertEqual(entries.first?.video?.bvid, "BV1ok")
        XCTAssertEqual(entries.first?.authorMid, 946974, "字符串 mid 也认")
        XCTAssertEqual(entries.first?.video?.playText, "12345", "裸数字播放量转成文字直接显示")
    }

    // MARK: - 关注的 UP 主

    func testPortalDecodesUpListWithDefaultUpdateFlag() throws {
        let json = """
        {"up_list": [
          {"mid": 1, "uname": "有更新", "face": "//i0.hdslb.com/a.jpg", "has_update": true},
          {"mid": 2, "uname": "没有字段", "face": "https://i0.hdslb.com/b.jpg"}
        ]}
        """
        let payload = try JSONDecoder().decode(DynamicPortalPayload.self, from: Data(json.utf8))
        let ups = try XCTUnwrap(payload.upList)

        XCTAssertEqual(ups.count, 2)
        XCTAssertTrue(ups[0].hasUpdate)
        XCTAssertEqual(ups[0].secureAvatarURL?.absoluteString, "https://i0.hdslb.com/a.jpg")
        XCTAssertFalse(ups[1].hasUpdate, "缺 has_update 时按「没有更新」处理，不画红点")
    }

    func testPortalSkipsUpsWithoutMid() throws {
        let json = """
        {"up_list": [{"uname": "没有 mid"}, {"mid": 7, "uname": "正常", "face": "", "has_update": 1}]}
        """
        let payload = try JSONDecoder().decode(DynamicPortalPayload.self, from: Data(json.utf8))
        let ups = try XCTUnwrap(payload.upList)

        XCTAssertEqual(ups.map(\.mid), [7], "没有 mid 的条目点不进空间页，直接跳过")
        XCTAssertTrue(ups[0].hasUpdate, "has_update 是 1 也算有更新")
    }

    // MARK: - UP 主投稿列表

    func testSpaceVideoHandlesHiddenPlayCount() throws {
        let json = """
        {"list": {"vlist": [
          {"aid": 114514, "bvid": "BV1xx", "title": "标题", "pic": "//i0.hdslb.com/p.jpg",
           "length": "12:34", "play": "--", "author": "某 UP", "mid": 1, "created": 1788058800}
        ]}, "page": {"count": 40, "pn": 1, "ps": 30}}
        """
        let page = try JSONDecoder().decode(SpaceVideoPage.self, from: Data(json.utf8))
        let video = try XCTUnwrap(page.videos.first)

        XCTAssertEqual(video.aid, 114514)
        XCTAssertEqual(video.length, "12:34")
        XCTAssertEqual(video.play, 0, "隐藏播放量的稿件返回的是 `--`，当作 0")
        XCTAssertTrue(page.hasMore(after: 30), "总共 40 条，取到 30 条时还有下一页")
        XCTAssertFalse(page.hasMore(after: 40))

        let card = video.asFollowedVideo(avatar: "//i0.hdslb.com/face.jpg")
        XCTAssertEqual(card.playText, "", "播放量为 0 时不显示这一项")
        XCTAssertEqual(card.durationText, "12:34")
    }

    // MARK: - UP 主名片

    func testSpaceCardFallsBackToTopLevelBanner() throws {
        // 头图在这个接口里出现过两个位置，只解 card.space 的话另一种响应就没有头图。
        let json = """
        {"card": {"name": "某 UP", "face": "https://i0.hdslb.com/f.jpg", "attention": 7,
                  "level_info": {"current_level": 5}, "vip": {"status": 1}},
         "space": {"l_img": "//i0.hdslb.com/top-banner.jpg"},
         "following": true, "follower": 1234, "like_num": 5678, "archive_count": 9}
        """
        let card = try JSONDecoder().decode(SpaceCardPayload.self, from: Data(json.utf8)).asSpaceCard(mid: 42)

        XCTAssertEqual(card.secureBannerURL?.absoluteString, "https://i0.hdslb.com/top-banner.jpg")
        XCTAssertEqual(card.level, 5)
        XCTAssertTrue(card.isVIP)
        XCTAssertEqual(card.follower, 1234)
        XCTAssertEqual(card.followingCount, 7)
        XCTAssertEqual(card.likeCount, 5678)
        XCTAssertTrue(card.isFollowing)
    }

    func testSpaceCardWithoutBannerLeavesItNil() throws {
        let card = try JSONDecoder()
            .decode(SpaceCardPayload.self, from: Data(#"{"card": {"name": "无头图"}}"#.utf8))
            .asSpaceCard(mid: 1)

        XCTAssertNil(card.secureBannerURL, "没有头图时交给界面画渐变，而不是显示图裂占位")
        XCTAssertEqual(card.name, "无头图")
    }

    // MARK: - 搜索联想

    func testSuggestPayloadDropsDuplicatesAndEmptyValues() throws {
        let json = """
        {"code": 0, "result": {"tag": [
          {"value": "猫和老鼠", "name": "<em>猫</em>和老鼠"},
          {"value": "猫和老鼠", "name": "<em>猫</em>和老鼠"},
          {"value": "", "name": ""},
          {"value": "猫咪", "name": "<em>猫</em>咪"}
        ]}}
        """
        let payload = try JSONDecoder().decode(SearchSuggestPayload.self, from: Data(json.utf8))

        XCTAssertEqual(payload.suggestions.map(\.value), ["猫和老鼠", "猫咪"])
    }

    func testSuggestPayloadTreatsEmptyResultArrayAsNoSuggestions() throws {
        // 一个候选词都没有时，服务端把 result 从对象换成了空数组，code 也不是 0。
        let json = """
        {"code": 3, "result": [], "total_count": 0}
        """
        let payload = try JSONDecoder().decode(SearchSuggestPayload.self, from: Data(json.utf8))

        XCTAssertTrue(payload.suggestions.isEmpty)
    }

    // MARK: - 搜索页状态

    @MainActor
    func testSearchViewModelShowsSuggestionsUntilKeywordIsSubmitted() {
        let viewModel = SearchViewModel()
        XCTAssertFalse(viewModel.isShowingSuggestions, "还没输入时不显示候选词")

        viewModel.query = "  猫咪 "
        XCTAssertEqual(viewModel.trimmedQuery, "猫咪")
        XCTAssertTrue(viewModel.isShowingSuggestions)

        viewModel.submit()
        XCTAssertEqual(viewModel.submittedKeyword, "猫咪")
        XCTAssertFalse(viewModel.isShowingSuggestions, "搜过之后页面换成结果列表")

        viewModel.query = "猫咪 视频"
        XCTAssertTrue(viewModel.isShowingSuggestions, "继续改输入又回到候选词")
    }

    @MainActor
    func testSearchViewModelClearsResultsWhenSubmittingEmptyKeyword() {
        let viewModel = SearchViewModel()
        viewModel.submit(keyword: "   ")

        XCTAssertEqual(viewModel.query, "   ")
        XCTAssertTrue(viewModel.submittedKeyword.isEmpty)
        XCTAssertTrue(viewModel.results.isEmpty)
    }

    // MARK: - 相对时间

    func testRelativeTimeText() {
        let now = Int(Date().timeIntervalSince1970)
        XCTAssertEqual((now - 30).biliRelativeTimeText, "刚刚")
        XCTAssertEqual((now - 23 * 60).biliRelativeTimeText, "23分钟前")
        XCTAssertEqual((now - 3 * 3600).biliRelativeTimeText, "3小时前")
    }
}
