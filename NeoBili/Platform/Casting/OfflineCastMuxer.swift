import NeoBiliDomain
import AVFoundation
import Foundation

/// 将离线缓存的分离音视频轨（如 DASH 的 video-0.m4s + audio.m4s）无损封装为单个临时 MP4，供 DLNA 电视播放。
actor OfflineCastMuxer {
    private let directory: URL
    private var cachedOutputs: [String: URL] = [:]

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoBiliCastMux", isDirectory: true)
    }

    func muxToMP4(videoURL: URL, audioURL: URL) async throws -> URL {
        let key = "\(videoURL.path)|\(audioURL.path)"
        if let existing = cachedOutputs[key], FileManager.default.fileExists(atPath: existing.path) {
            return existing
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let jobID = UUID().uuidString
        let outputURL = directory.appendingPathComponent("\(jobID).mp4")

        // AVURLAsset 依赖文件扩展名识别容器；B 站离线 DASH 缓存以 .m4s 保存，
        // 本质是 ISO BMFF / MP4。优先用同卷硬链接（零拷贝且避免真机 mediaserverd 拒绝跟随符号链接），
        // 不可硬链接时回退到临时复制。
        let readableVideoURL = try makeReadableAssetURL(for: videoURL, fallbackExtension: "mp4", jobID: "\(jobID)-v")
        let readableAudioURL = try makeReadableAssetURL(for: audioURL, fallbackExtension: "m4a", jobID: "\(jobID)-a")
        defer {
            if readableVideoURL != videoURL { try? FileManager.default.removeItem(at: readableVideoURL) }
            if readableAudioURL != audioURL { try? FileManager.default.removeItem(at: readableAudioURL) }
        }

        let videoAsset = AVURLAsset(url: readableVideoURL)
        let audioAsset = AVURLAsset(url: readableAudioURL)
        let composition = AVMutableComposition()

        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first,
              let compositionVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw CastError.offlineMuxFailed(String(localized: "未找到有效的视频轨道"))
        }
        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideo,
            at: .zero
        )
        compositionVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)

        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        if let sourceAudio = audioTracks.first,
           let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let audioDuration = try await audioAsset.load(.duration)
            let rangeDuration = CMTimeMinimum(videoDuration, audioDuration)
            try compositionAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: rangeDuration),
                of: sourceAudio,
                at: .zero
            )
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw CastError.offlineMuxFailed(String(localized: "当前编码不支持快速封装"))
        }
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            try await exportSession.export(to: outputURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw CastError.offlineMuxFailed(error.localizedDescription)
        }

        cachedOutputs[key] = outputURL
        return outputURL
    }

    private func makeReadableAssetURL(for sourceURL: URL, fallbackExtension: String, jobID: String) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        let supported = Set(["mp4", "m4v", "m4a", "mov"])
        if supported.contains(ext) {
            return sourceURL
        }
        let linkURL = directory.appendingPathComponent("\(jobID).\(fallbackExtension)")
        try? FileManager.default.removeItem(at: linkURL)
        do {
            try FileManager.default.linkItem(at: sourceURL, to: linkURL)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: linkURL)
        }
        return linkURL
    }

    func cleanup() {
        for url in cachedOutputs.values {
            try? FileManager.default.removeItem(at: url)
        }
        cachedOutputs.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
