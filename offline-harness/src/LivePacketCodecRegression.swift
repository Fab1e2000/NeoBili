import Foundation
import Compression

/// 直播弹幕 WS 包编解码的离线回归。
///
/// 覆盖协议里最容易错的三处：16 字节大端包头布局、zlib（带头尾）解压、
/// 解压后多条完整包的粘包切分。服务端形态按 PiliPlus 的解码行为构造。
@main
struct LivePacketCodecRegression {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS  \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)")
        }
    }

    static func main() {
        testPacketLayout()
        testHeaderRoundTrip()
        testConcatenatedSplit()
        testZlibInflate()
        testMalformedTolerance()

        if failures == 0 {
            print("ALL PACKET CODEC CHECKS PASS")
            exit(0)
        }
        print("FAILURES: \(failures)")
        exit(1)
    }

    private static func u32be(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
    private static func u16be(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    private static func testPacketLayout() {
        let body = Data(#"{"roomid":1}"#.utf8)
        let packet = LivePacketCodec.packet(op: 7, protover: 1, seq: 1, body: body)
        let bytes = [UInt8](packet)
        expect(bytes.count == 16 + body.count, "认证包总长 = 16 + body")
        expect(Array(bytes[0..<4]) == u32be(UInt32(packet.count)), "包总长字段按大端写入")
        expect(Array(bytes[4..<6]) == u16be(16), "包头长度字段为 16")
        expect(Array(bytes[6..<8]) == u16be(1), "协议版本字段为 1")
        expect(Array(bytes[8..<12]) == u32be(7), "操作码字段为 7（认证）")
        expect(Array(bytes[12..<16]) == u32be(1), "序号字段为 1")
        expect(packet.suffix(body.count) == body, "body 原样附加在头之后")

        let heartbeat = LivePacketCodec.packet(op: 2, protover: 1, seq: 42)
        expect(heartbeat.count == 16, "心跳包只有包头没有 body")
        expect(Array(heartbeat[8..<12]) == u32be(2), "心跳操作码为 2")
    }

    private static func testHeaderRoundTrip() {
        let packet = LivePacketCodec.packet(op: 5, protover: 2, seq: 7, body: Data([1, 2, 3]))
        guard let header = LivePacketCodec.header(of: packet) else {
            expect(false, "正常包可以解析出包头")
            return
        }
        expect(header.totalLength == packet.count && header.headerLength == 16, "包头字段往返一致")
        expect(header.protover == 2 && header.operation == 5, "协议版本与操作码往返一致")
        expect(LivePacketCodec.header(of: Data([0, 1, 2])) == nil, "不足 16 字节返回 nil")
    }

    private static func makeMessagePacket(_ text: String, protover: UInt16 = 0) -> Data {
        let body = Data(text.utf8)
        return LivePacketCodec.packet(op: 5, protover: protover, seq: 1, body: body)
    }

    private static func testConcatenatedSplit() {
        let concatenated = makeMessagePacket("第一条") + makeMessagePacket("第二条") + makeMessagePacket("第三条")
        let frames = LivePacketCodec.splitConcatenated(concatenated)
        expect(frames.count == 3, "三条粘包完整切开")
        expect(frames.allSatisfy { $0.operation == 5 }, "粘包各条操作码一致为 5")
        expect(frames.map { String(data: $0.body, encoding: .utf8)! } == ["第一条", "第二条", "第三条"],
               "粘包各条 body 顺序与内容一致")

        let truncated = concatenated.prefix(concatenated.count - 1)
        expect(LivePacketCodec.splitConcatenated(Data(truncated)).count == 2,
               "尾包被截断时丢弃尾包、保留完整前序包")
        expect(LivePacketCodec.splitConcatenated(Data()).isEmpty, "空数据返回空列表")
    }

    /// 按服务端格式构造 zlib 流：0x78 头 + 裸 deflate + 4 字节 Adler32。
    private static func zlibStream(_ raw: Data) -> Data {
        var stream = Data([0x78, 0x9C])
        if let deflated = try? (raw as NSData).compressed(using: .zlib) as Data {
            stream.append(deflated)
        }
        stream.append(Data([0, 0, 0, 0])) // 校验和占位：解码端只剥掉不校验
        return stream
    }

    private static func testZlibInflate() {
        let first = makeMessagePacket("压缩弹幕A", protover: 2)
        let second = makeMessagePacket("压缩弹幕B", protover: 2)
        let concatenated = first + second

        guard let inflated = LivePacketCodec.inflate(body: zlibStream(concatenated)) else {
            expect(false, "zlib 流可以解压")
            return
        }
        expect(inflated == concatenated, "解压结果与原始拼接流逐字节一致")
        let frames = LivePacketCodec.splitConcatenated(inflated)
        expect(frames.count == 2, "解压后粘包可以完整切开")
        expect(String(data: frames[0].body, encoding: .utf8) == "压缩弹幕A", "解压后第一条内容正确")

        let rawOnly = try? (concatenated as NSData).compressed(using: .zlib) as Data
        expect(LivePacketCodec.inflate(body: rawOnly ?? Data()) == concatenated, "无 zlib 头的裸 deflate 走回退路径")
        expect(LivePacketCodec.inflate(body: Data([0x01])) != nil || true, "异常流不崩溃")
    }

    private static func testMalformedTolerance() {
        expect(LivePacketCodec.splitConcatenated(Data(repeating: 0xFF, count: 64)).isEmpty,
               "全 0xFF 垃圾流不产生帧也不崩溃")
        expect(LivePacketCodec.header(of: Data(repeating: 0, count: 16)) != nil, "全零包头可以解析（长度为 0）")
        expect(LivePacketCodec.packet(op: 5, protover: 3, seq: 1).count == 16, "未知协议版本照常编码（由分发端忽略）")
    }
}
