import NeoBiliDomain
import Foundation
import Libavcodec
import Libavformat
import Libavutil

/// 基于 MPVKit 内置 libavformat 的实时无损混流器：
/// 将远端（或本地）DASH 视频轨 + 可选音频轨零重编码封装为 Fragmented MP4 字节流，
/// 支持任意画质（含 1080P60/4K）与独立音质（含 Hi-Res/杜比），并支持按时间偏移精准起播。
enum DASHCastRemuxer {
    private static let avNoPTSValue: Int64 = Int64(bitPattern: 0x8000_0000_0000_0000)

    final class ChunkWriter: @unchecked Sendable {
        private let onChunk: (Data) -> Bool
        private(set) var aborted = false

        init(onChunk: @escaping (Data) -> Bool) {
            self.onChunk = onChunk
        }

        func emit(_ bytes: UnsafePointer<UInt8>, count: Int) -> Int32 {
            guard !aborted, count > 0 else { return -1 }
            let data = Data(bytes: bytes, count: count)
            if onChunk(data) {
                return Int32(count)
            } else {
                aborted = true
                return -1
            }
        }
    }

    /// 阻塞执行实时无损混流，请在后台线程调用；返回 `onChunk` 为 `false` 或 Task 取消时立刻中止并释放全部资源。
    static func stream(
        videoURL: URL,
        audioURL: URL?,
        headers: [String: String],
        startPosition: TimeInterval = 0,
        isCancelled: () -> Bool = { false },
        onChunk: @escaping (Data) -> Bool
    ) throws {
        var videoCtx: UnsafeMutablePointer<AVFormatContext>?
        var audioCtx: UnsafeMutablePointer<AVFormatContext>?
        var outCtx: UnsafeMutablePointer<AVFormatContext>?
        var ioCtx: UnsafeMutablePointer<AVIOContext>?
        var avioBuffer: UnsafeMutablePointer<UInt8>?

        defer {
            if let outCtx {
                if let pb = outCtx.pointee.pb, pb == ioCtx {
                    outCtx.pointee.pb = nil
                }
                avformat_free_context(outCtx)
            }
            if let io = ioCtx {
                if let buf = io.pointee.buffer {
                    av_free(buf)
                }
                avio_context_free(&ioCtx)
            } else if let avioBuffer {
                av_free(avioBuffer)
            }
            if videoCtx != nil {
                avformat_close_input(&videoCtx)
            }
            if audioCtx != nil {
                avformat_close_input(&audioCtx)
            }
        }

        videoCtx = try openInput(url: videoURL, headers: headers)
        guard let vCtx = videoCtx else {
            throw CastError.transportFailed(String(localized: "无法打开 DASH 视频流"))
        }
        let videoInIndex = av_find_best_stream(vCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        guard videoInIndex >= 0, let vStreams = vCtx.pointee.streams, let vInStream = vStreams[Int(videoInIndex)] else {
            throw CastError.transportFailed(String(localized: "未找到有效的 DASH 视频轨道"))
        }

        var audioInIndex: Int32 = -1
        var aInStream: UnsafeMutablePointer<AVStream>?
        if let audioURL {
            audioCtx = try openInput(url: audioURL, headers: headers)
            if let aCtx = audioCtx {
                let idx = av_find_best_stream(aCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
                if idx >= 0, let aStreams = aCtx.pointee.streams {
                    audioInIndex = idx
                    aInStream = aStreams[Int(idx)]
                }
            }
        }

        guard !isCancelled() else { return }

        // 按起始秒数 Seek 到目标关键帧（利用 B 站 .m4s sidx 索引，单次 Range 请求直达）。
        if startPosition > 0.5 {
            let targetUS = Int64(startPosition * Double(AV_TIME_BASE))
            _ = av_seek_frame(vCtx, -1, targetUS, AVSEEK_FLAG_BACKWARD)
            if let aCtx = audioCtx, audioInIndex >= 0 {
                _ = av_seek_frame(aCtx, -1, targetUS, AVSEEK_FLAG_BACKWARD)
            }
        }

        let allocStatus = avformat_alloc_output_context2(&outCtx, nil, "mp4", nil)
        guard allocStatus >= 0, let oCtx = outCtx else {
            throw CastError.transportFailed(String(localized: "无法初始化 MP4 混流上下文"))
        }

        guard let vOutStream = avformat_new_stream(oCtx, nil) else {
            throw CastError.transportFailed(String(localized: "无法创建输出视频轨"))
        }
        guard avcodec_parameters_copy(vOutStream.pointee.codecpar, vInStream.pointee.codecpar) >= 0 else {
            throw CastError.transportFailed(String(localized: "无法复制视频编码参数"))
        }
        vOutStream.pointee.codecpar.pointee.codec_tag = 0
        vOutStream.pointee.time_base = vInStream.pointee.time_base

        var aOutStream: UnsafeMutablePointer<AVStream>?
        if let aInStream {
            if let stream = avformat_new_stream(oCtx, nil),
               avcodec_parameters_copy(stream.pointee.codecpar, aInStream.pointee.codecpar) >= 0 {
                stream.pointee.codecpar.pointee.codec_tag = 0
                stream.pointee.time_base = aInStream.pointee.time_base
                aOutStream = stream
            }
        }

        let writer = ChunkWriter(onChunk: onChunk)
        let bufferSize: Int32 = 65_536
        avioBuffer = av_malloc(Int(bufferSize))?.assumingMemoryBound(to: UInt8.self)
        guard let rawBuffer = avioBuffer else {
            throw CastError.transportFailed(String(localized: "混流缓冲区分配失败"))
        }

        let opaque = Unmanaged.passUnretained(writer).toOpaque()
        ioCtx = avio_alloc_context(
            rawBuffer,
            bufferSize,
            1,
            opaque,
            nil,
            { opaquePtr, buf, bufSize in
                guard let opaquePtr, let buf else { return -1 }
                let box = Unmanaged<ChunkWriter>.fromOpaque(opaquePtr).takeUnretainedValue()
                return box.emit(buf, count: Int(bufSize))
            },
            nil
        )
        guard let io = ioCtx else {
            throw CastError.transportFailed(String(localized: "无法创建自定义输出流"))
        }
        io.pointee.seekable = 0
        oCtx.pointee.pb = io
        oCtx.pointee.flags |= AVFMT_FLAG_CUSTOM_IO

        var muxOpts: OpaquePointer?
        av_dict_set(&muxOpts, "movflags", "frag_keyframe+empty_moov+default_base_moof", 0)
        // 允许封装 FLAC (Hi-Res) 等扩展音轨进 MP4 容器。
        av_dict_set(&muxOpts, "strict", "experimental", 0)
        defer { av_dict_free(&muxOpts) }

        let headerStatus = avformat_write_header(oCtx, &muxOpts)
        guard headerStatus >= 0 else {
            throw CastError.transportFailed(String(localized: "写入混流文件头失败（\(headerStatus)）"))
        }

        guard let vPkt = av_packet_alloc(), let aPkt = av_packet_alloc() else {
            throw CastError.transportFailed(String(localized: "无法分配数据包"))
        }
        var videoPacket: UnsafeMutablePointer<AVPacket>? = vPkt
        var audioPacket: UnsafeMutablePointer<AVPacket>? = aPkt
        defer {
            av_packet_free(&videoPacket)
            av_packet_free(&audioPacket)
        }

        var hasVideo = readNextPacket(from: vCtx, streamIndex: videoInIndex, into: vPkt)
        var hasAudio = (audioCtx != nil && aOutStream != nil)
            ? readNextPacket(from: audioCtx!, streamIndex: audioInIndex, into: aPkt)
            : false

        // 以首个视频包的 DTS/PTS 作为公共零点基准，保证音画起点对齐且时间戳从 0 开始。
        var baseSeconds: Double?
        if hasVideo {
            baseSeconds = packetSeconds(vPkt, timeBase: vInStream.pointee.time_base)
        } else if hasAudio, let aInStream {
            baseSeconds = packetSeconds(aPkt, timeBase: aInStream.pointee.time_base)
        }
        let originSeconds = baseSeconds ?? 0

        var lastVideoDTS: Int64 = -1
        var lastAudioDTS: Int64 = -1

        while (hasVideo || hasAudio) && !writer.aborted && !isCancelled() {
            let vSec = hasVideo ? packetSeconds(vPkt, timeBase: vInStream.pointee.time_base) : Double.infinity
            let aSec = (hasAudio && aInStream != nil)
                ? packetSeconds(aPkt, timeBase: aInStream!.pointee.time_base)
                : Double.infinity

            if hasVideo && vSec <= aSec {
                let written = writeRebasedPacket(
                    vPkt,
                    inTimeBase: vInStream.pointee.time_base,
                    outStream: vOutStream,
                    outCtx: oCtx,
                    originSeconds: originSeconds,
                    lastDTS: &lastVideoDTS
                )
                av_packet_unref(vPkt)
                if !written { break }
                hasVideo = readNextPacket(from: vCtx, streamIndex: videoInIndex, into: vPkt)
            } else if hasAudio, let aCtx = audioCtx, let aIn = aInStream, let aOut = aOutStream {
                // 跳过早于视频起始关键帧的音频帧，确保 Seek 后音画同步。
                if aSec + 0.05 >= originSeconds {
                    let written = writeRebasedPacket(
                        aPkt,
                        inTimeBase: aIn.pointee.time_base,
                        outStream: aOut,
                        outCtx: oCtx,
                        originSeconds: originSeconds,
                        lastDTS: &lastAudioDTS
                    )
                    av_packet_unref(aPkt)
                    if !written { break }
                } else {
                    av_packet_unref(aPkt)
                }
                hasAudio = readNextPacket(from: aCtx, streamIndex: audioInIndex, into: aPkt)
            } else {
                break
            }
        }

        if hasVideo { av_packet_unref(vPkt) }
        if hasAudio { av_packet_unref(aPkt) }

        if !writer.aborted && !isCancelled() {
            _ = av_write_trailer(oCtx)
            avio_flush(io)
        }
    }

    private static func openInput(url: URL, headers: [String: String]) throws -> UnsafeMutablePointer<AVFormatContext> {
        var ctx: UnsafeMutablePointer<AVFormatContext>?
        var opts: OpaquePointer?
        defer { av_dict_free(&opts) }

        let inputPath: String
        if url.isFileURL {
            inputPath = url.path
        } else {
            inputPath = url.absoluteString
            var headerLines: [String] = []
            for (key, value) in headers {
                if key.caseInsensitiveCompare("User-Agent") == .orderedSame {
                    av_dict_set(&opts, "user_agent", value, 0)
                } else {
                    headerLines.append("\(key): \(value)")
                }
            }
            if !headerLines.isEmpty {
                let joined = headerLines.joined(separator: "\r\n") + "\r\n"
                av_dict_set(&opts, "headers", joined, 0)
            }
            av_dict_set(&opts, "reconnect", "1", 0)
            av_dict_set(&opts, "reconnect_streamed", "1", 0)
            av_dict_set(&opts, "reconnect_delay_max", "5", 0)
            av_dict_set(&opts, "rw_timeout", "15000000", 0)
        }

        let openStatus = avformat_open_input(&ctx, inputPath, nil, &opts)
        guard openStatus >= 0, let opened = ctx else {
            throw CastError.transportFailed(String(localized: "无法打开媒体流（\(openStatus)）"))
        }
        let infoStatus = avformat_find_stream_info(opened, nil)
        guard infoStatus >= 0 else {
            avformat_close_input(&ctx)
            throw CastError.transportFailed(String(localized: "无法解析媒体轨道信息（\(infoStatus)）"))
        }
        return opened
    }

    private static func readNextPacket(
        from ctx: UnsafeMutablePointer<AVFormatContext>,
        streamIndex: Int32,
        into packet: UnsafeMutablePointer<AVPacket>
    ) -> Bool {
        while av_read_frame(ctx, packet) >= 0 {
            if packet.pointee.stream_index == streamIndex {
                return true
            }
            av_packet_unref(packet)
        }
        return false
    }

    private static func packetSeconds(_ packet: UnsafeMutablePointer<AVPacket>, timeBase: AVRational) -> Double {
        let raw = packet.pointee.dts != avNoPTSValue ? packet.pointee.dts : packet.pointee.pts
        guard raw != avNoPTSValue, timeBase.den > 0 else { return 0 }
        return Double(raw) * Double(timeBase.num) / Double(timeBase.den)
    }

    private static func writeRebasedPacket(
        _ packet: UnsafeMutablePointer<AVPacket>,
        inTimeBase: AVRational,
        outStream: UnsafeMutablePointer<AVStream>,
        outCtx: UnsafeMutablePointer<AVFormatContext>,
        originSeconds: Double,
        lastDTS: inout Int64
    ) -> Bool {
        let outTimeBase = outStream.pointee.time_base
        let originInTicks: Int64 = (inTimeBase.num > 0 && inTimeBase.den > 0)
            ? Int64((originSeconds * Double(inTimeBase.den) / Double(inTimeBase.num)).rounded())
            : 0

        if packet.pointee.dts != avNoPTSValue {
            packet.pointee.dts = max(0, packet.pointee.dts - originInTicks)
        }
        if packet.pointee.pts != avNoPTSValue {
            packet.pointee.pts = max(0, packet.pointee.pts - originInTicks)
        }

        av_packet_rescale_ts(packet, inTimeBase, outTimeBase)

        if packet.pointee.dts == avNoPTSValue {
            packet.pointee.dts = max(0, lastDTS + 1)
        }
        if packet.pointee.dts <= lastDTS {
            packet.pointee.dts = lastDTS + 1
        }
        if packet.pointee.pts == avNoPTSValue || packet.pointee.pts < packet.pointee.dts {
            packet.pointee.pts = packet.pointee.dts
        }
        lastDTS = packet.pointee.dts
        packet.pointee.stream_index = outStream.pointee.index
        packet.pointee.pos = -1

        return av_interleaved_write_frame(outCtx, packet) >= 0
    }
}
