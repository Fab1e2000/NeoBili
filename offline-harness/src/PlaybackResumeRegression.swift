import Foundation

@MainActor
@main
struct PlaybackResumeRegression {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL")  \(message)")
        if !condition { failures += 1 }
    }

    static func main() {
        let suite = "neobili.resume.harness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackProgressStore(defaults: defaults)
        store.save(bvid: "BVResume", cid: 1, position: 47.25, duration: 300)
        store.save(bvid: "BVResume", cid: 2, position: 81, duration: 300)
        store.save(bvid: "BVAnother", cid: 1, position: 14, duration: 300)
        let reopened = PlaybackProgressStore(defaults: defaults)
        expect(reopened.resumePosition(bvid: "BVResume", cid: 1) == 47.25,
               "新建存储实例后从原位置恢复（持久化）")
        expect(reopened.resumePosition(bvid: "BVResume", cid: 2) == 81,
               "同一视频各分 P 独立记忆")
        expect(reopened.resumePosition(bvid: "BVAnother", cid: 1) == 14,
               "不同视频相同 cid 不互相覆盖")

        reopened.save(bvid: "BVResume", cid: 1, position: .nan, duration: 300)
        reopened.save(bvid: "BVResume", cid: 1, position: -.infinity, duration: 300)
        expect(reopened.resumePosition(bvid: "BVResume", cid: 1) == 47.25,
               "无效播放器数值不能覆盖已保存进度")
        reopened.save(bvid: "BVResume", cid: 1, position: 0, duration: 300)
        expect(PlaybackProgressStore(defaults: defaults).resumePosition(bvid: "BVResume", cid: 1) == 0,
               "主动拖回片头会持久清除旧位置")

        reopened.save(bvid: "BVEnd", cid: 1, position: 299, duration: 300)
        expect(reopened.resumePosition(bvid: "BVEnd", cid: 1) == 0, "片尾不足 5 秒从头播放")
        reopened.save(bvid: "BVShort", cid: 1, position: 26, duration: 30)
        expect(reopened.resumePosition(bvid: "BVShort", cid: 1) == 26, "短视频保留最后几秒，仅最后 2% 视为看完")
        reopened.save(bvid: "BVChanged", cid: 1, position: 90, duration: 300)
        expect(reopened.resumePosition(bvid: "BVChanged", cid: 1, duration: 80) == 0,
               "视频变短时不会从超出新时长的位置打开")
        reopened.save(bvid: "BVUnknown", cid: 1, position: 50, duration: 0)
        expect(reopened.resumePosition(bvid: "BVUnknown", cid: 1) == 50, "尚未知时长也能记住有效位置")

        var state = PlaybackResumeState(position: 120)
        expect(!state.hasUpdatedPosition, "仅进入加载页并未产生可以覆盖旧记录的新位置")
        state.prepareForOpen(at: 120)
        expect(!state.accept(position: 0) && state.position == 120,
               "开流前后短暂 0 不能把恢复点归零")
        expect(state.accept(position: 120.5), "解码器抵达恢复点后接受连续进度")
        state.prepareForOpen(at: state.position)
        expect(!state.accept(position: 0) && state.position == 120.5,
               "切清晰度、备用源、重试时同样保护最后位置")
        expect(state.confirm(position: 124) && state.accept(position: 125),
               "权威 seek 完成事件解除偏差超过 2 秒的等待")
        state.seek(to: 12)
        expect(!state.accept(position: 125) && state.position == 12,
               "向后拖动后迟到的旧位置不能覆盖目标")
        expect(state.accept(position: 12.1), "向后拖动完成后继续正常记忆")
        state.seek(to: 0)
        expect(!state.accept(position: 12.1) && state.accept(position: 0),
               "拖回开头允许真正的 0，屏蔽迟到旧位置")
        state.complete()
        expect(state.isCompleted && !state.accept(position: 299) && !state.confirm(position: 0),
               "EOF 后的尾随事件不能重新写回片尾进度")
        state.seek(to: 0)
        expect(!state.isCompleted && state.accept(position: 1), "重播后重新记忆新进度")

        let boundedSuite = "\(suite).bounded"
        let boundedDefaults = UserDefaults(suiteName: boundedSuite)!
        defer { boundedDefaults.removePersistentDomain(forName: boundedSuite) }
        var timestamp = Date(timeIntervalSince1970: 1)
        let bounded = PlaybackProgressStore(defaults: boundedDefaults, maximumEntries: 2, now: { timestamp })
        bounded.save(bvid: "old", cid: 1, position: 10, duration: 100)
        timestamp.addTimeInterval(1)
        bounded.save(bvid: "second", cid: 1, position: 20, duration: 100)
        timestamp.addTimeInterval(1)
        bounded.save(bvid: "latest", cid: 1, position: 30, duration: 100)
        expect(bounded.resumePosition(bvid: "old", cid: 1) == 0
               && bounded.resumePosition(bvid: "latest", cid: 1) == 30,
               "记录数量有上限，优先保留最近观看的视频")
        if failures > 0 { exit(1) }
        print("ALL PLAYBACK RESUME CHECKS PASS")
    }
}
