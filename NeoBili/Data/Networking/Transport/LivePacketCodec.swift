import Foundation
import Compression

/// B 站直播弹幕 WebSocket 的二进制包编解码。
///
/// 纯函数、无状态，协议细节对齐 PiliPlus（lib/tcp/live.dart）：
/// 16 字节大端包头，protover 2 的 body 是 zlib 压缩的多条完整包拼接。
/// 单独成文件是为了能在 macOS 离线 harness 上直接测试。
enum LivePacketCodec {
    struct FrameHeader {
        let totalLength: Int
        let headerLength: Int
        let protover: UInt16
        let operation: UInt32
    }

    /// 操作码：2 客户端心跳、3 心跳回复（含人气）、5 普通消息、7 认证、8 认证回复。
    static func packet(op: UInt32, protover: UInt16, seq: UInt32, body: Data = Data()) -> Data {
        var data = Data(capacity: 16 + body.count)
        append(UInt32(16 + body.count).bigEndian, to: &data)
        append(UInt16(16).bigEndian, to: &data)
        append(protover.bigEndian, to: &data)
        append(op.bigEndian, to: &data)
        append(seq.bigEndian, to: &data)
        data.append(body)
        return data
    }

    /// 解析包头；数据不足 16 字节返回 nil。
    static func header(of data: Data, offset: Int = 0) -> FrameHeader? {
        guard offset >= 0, offset <= data.count, data.count - offset >= 16 else { return nil }
        return data.withUnsafeBytes { bytes in
            FrameHeader(
                totalLength: Int(UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))),
                headerLength: Int(UInt16(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt16.self))),
                protover: UInt16(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + 6, as: UInt16.self)),
                operation: UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self))
            )
        }
    }

    /// 一帧解压后的内容按包边界切分；返回 (操作码, body) 列表。
    /// 半包/坏包直接截断丢弃（与 PiliPlus 的静默容错一致）。
    static func splitConcatenated(_ data: Data) -> [(operation: UInt32, body: Data)] {
        var result: [(operation: UInt32, body: Data)] = []
        var offset = 0
        while data.count - offset >= 16 {
            guard let header = header(of: data, offset: offset),
                  header.headerLength >= 16,
                  header.totalLength >= header.headerLength,
                  data.count - offset >= header.totalLength else { break }
            // Copy only each message body once, never the entire unconsumed tail.
            // Use startIndex so sliced Data is accepted too.
            let start = data.startIndex + offset
            let body = data.subdata(in: (start + header.headerLength)..<(start + header.totalLength))
            result.append((header.operation, body))
            offset += header.totalLength
        }
        return result
    }

    /// protover 2 的 zlib 解压。服务端流带 zlib 头（0x78…）和 4 字节 Adler32
    /// 尾，系统 `Compression` 的 `.zlib` 只认裸 deflate：先剥头尾再解；
    /// 异常流退回按裸 deflate 直接解一次。
    static func inflate(body: Data) -> Data? {
        if body.count > 6, body.prefix(1) == Data([0x78]) {
            let stripped = body.subdata(in: 2..<(body.count - 4))
            if let result = try? (stripped as NSData).decompressed(using: .zlib) as Data {
                return result
            }
        }
        return try? (body as NSData).decompressed(using: .zlib) as Data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }
}
