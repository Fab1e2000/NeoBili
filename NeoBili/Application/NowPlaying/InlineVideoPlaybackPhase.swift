/// playing 信号可能先于解码首帧到达，加载与真正暂停必须分开判断。
enum InlineVideoPlaybackPhase: Equatable {
    case loading
    case playing
    case paused

    init(isPlaying: Bool, hasRenderedFirstFrame: Bool, isLoading: Bool) {
        if !hasRenderedFirstFrame || isLoading {
            self = .loading
        } else {
            self = isPlaying ? .playing : .paused
        }
    }
}
