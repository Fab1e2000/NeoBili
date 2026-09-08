import Foundation

@main struct VideoEntranceRegression {
    @MainActor static func main() {
        let initial = VideoResolutionBatch(ids: ["A", "B", "C"], generation: 0, enabled: true, minimumSeconds: 30)
        let replacement = VideoResolutionBatch(ids: ["D", "B", "C"], generation: 0, enabled: true, minimumSeconds: 30)
        let clock = VideoEntranceClock()
        clock.prepare(ids: Set(initial.ids), generation: initial.generation, reset: initial.resetsEntrance(comparedTo: nil))
        clock.admit(initial.ids)
        let oldStarts = clock.starts

        clock.prepare(ids: Set(replacement.ids), generation: replacement.generation,
                      reset: replacement.resetsEntrance(comparedTo: initial))
        precondition(clock.starts["B"] == oldStarts["B"] && clock.starts["C"] == oldStarts["C"], "单卡替换不得重播其余卡片")
        precondition(clock.starts["A"] == nil && clock.starts["D"] == nil, "仅新卡等待入场判断")
        clock.admit(replacement.ids)
        precondition(clock.starts["D"] != nil && clock.starts["B"] == oldStarts["B"] && clock.starts["C"] == oldStarts["C"])
        print("PASS  不感兴趣替换后，仅新卡入场；同排及其余卡片的动画起点不变")

        let deletion = VideoResolutionBatch(ids: ["B", "C"], generation: 0, enabled: true, minimumSeconds: 30)
        precondition(!deletion.resetsEntrance(comparedTo: replacement))
        let append = VideoResolutionBatch(ids: ["B", "C", "E"], generation: 0, enabled: true, minimumSeconds: 30)
        precondition(!append.resetsEntrance(comparedTo: deletion))
        print("PASS  删除与分页追加不触发整批重播")

        let refresh = VideoResolutionBatch(ids: replacement.ids, generation: 1, enabled: true, minimumSeconds: 30)
        clock.prepare(ids: Set(refresh.ids), generation: refresh.generation, reset: refresh.resetsEntrance(comparedTo: replacement))
        precondition(clock.starts.isEmpty && clock.generation == 1, "主动刷新仍须重播整批")
        let filter = VideoResolutionBatch(ids: refresh.ids, generation: 1, enabled: false, minimumSeconds: 30)
        let duration = VideoResolutionBatch(ids: refresh.ids, generation: 1, enabled: true, minimumSeconds: 60)
        precondition(filter.resetsEntrance(comparedTo: refresh) && duration.resetsEntrance(comparedTo: refresh))
        print("PASS  主动刷新、画幅过滤与时长设置仍触发整批入场")
    }
}
