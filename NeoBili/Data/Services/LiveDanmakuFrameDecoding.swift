import NeoBiliDomain
import Foundation

/// 一帧解码后的结果。认证结果只供连接内部使用，其余直接转为展示层事件。
enum LiveDanmakuDecodedFrame {
    case event(LiveDanmakuEvent)
    case authenticated
    case authRejected
}

/// zlib 解压、粘包拆分与 op=5 消息解析都是纯计算，不占用主线程。
enum LiveDanmakuFrameDecoding {
    static func decode(_ data: Data) -> [LiveDanmakuDecodedFrame] {
        var frames: [LiveDanmakuDecodedFrame] = []
        var offset = 0
        while data.count - offset >= 16 {
            guard let header = LivePacketCodec.header(of: data, offset: offset),
                  header.headerLength >= 16, header.totalLength >= header.headerLength,
                  header.totalLength <= data.count - offset else { return frames }
            let start = data.startIndex + offset
            let body = data.subdata(in: (start + header.headerLength)..<(start + header.totalLength))
            switch header.protover {
            case 0, 1:
                frames.append(contentsOf: dispatch(operation: header.operation, body: body))
            case 2:
                if let inflated = LivePacketCodec.inflate(body: body) {
                    for (operation, messageBody) in LivePacketCodec.splitConcatenated(inflated) {
                        frames.append(contentsOf: dispatch(operation: operation, body: messageBody))
                    }
                }
            default: break
            }
            offset += header.totalLength
        }
        return frames
    }

    static func decode(text: String) -> [LiveDanmakuDecodedFrame] {
        guard let data = text.data(using: .utf8) else { return [] }
        return dispatch(operation: 5, body: data)
    }

    private static func dispatch(operation: UInt32, body: Data) -> [LiveDanmakuDecodedFrame] {
        switch operation {
        case 3:
            // 心跳回复：前 4 字节大端人气值。
            guard body.count >= 4 else { return [] }
            var value: UInt32 = 0
            body.withUnsafeBytes { value = $0.loadUnaligned(as: UInt32.self) }
            return [.event(.popularity(Int(UInt32(bigEndian: value))))]
        case 5:
            guard let parsed = LiveDanmakuMessageParser.parse(body) else { return [] }
            return [.event(.parsed(parsed))]
        case 8:
            guard let reply = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  reply["code"] as? Int == 0 else { return [.authRejected] }
            return [.authenticated]
        default:
            return []
        }
    }
}

/// 接收循环把整帧交给这个 actor 解码；串行执行同时保持同一批消息的原始顺序。
actor LiveDanmakuFrameDecoder {
    func decode(_ data: Data) -> [LiveDanmakuDecodedFrame] { LiveDanmakuFrameDecoding.decode(data) }
    func decode(text: String) -> [LiveDanmakuDecodedFrame] { LiveDanmakuFrameDecoding.decode(text: text) }
}
