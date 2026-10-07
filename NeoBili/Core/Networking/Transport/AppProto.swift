import Foundation
import Compression

/// Bounded Protobuf and unary gRPC framing shared by requests, responses and behavior logs.
struct AppProto {
    enum Value { case integer(UInt64), bytes(Data) }
    enum Failure: Error { case malformed, oversized }
    let fields: [Int: [Value]]
    init(_ data: Data) throws {
        guard data.count <= 16 * 1024 * 1024 else { throw Failure.oversized }
        let bytes = [UInt8](data)
        var index = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < bytes.count else { throw Failure.malformed }
                let byte = bytes[index]; index += 1
                if shift == 63 && byte > 1 { throw Failure.malformed }
                value |= UInt64(byte & 127) << shift
                if byte < 128 { return value }
            }
            throw Failure.malformed
        }
        var result: [Int: [Value]] = [:]
        var count = 0
        while index < bytes.count {
            count += 1
            guard count <= 100_000 else { throw Failure.oversized }
            let tag = try varint(), number = tag >> 3
            guard number > 0, number <= UInt64(Int.max) else { throw Failure.malformed }
            let field = Int(number)
            switch tag & 7 {
            case 0: result[field, default: []].append(.integer(try varint()))
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - index) else { throw Failure.malformed }
                let end = index + Int(length)
                result[field, default: []].append(.bytes(Data(bytes[index..<end])))
                index = end
            case 1, 5:
                let length = tag & 7 == 1 ? 8 : 4
                guard bytes.count - index >= length else { throw Failure.malformed }
                index += length
            default: throw Failure.malformed
            }
        }
        fields = result
    }
    func number(_ field: Int) -> Int {
        guard case .integer(let value) = fields[field]?.first, value <= UInt64(Int.max) else { return 0 }
        return Int(value)
    }
    func data(_ field: Int) -> Data? {
        guard case .bytes(let data) = fields[field]?.first else { return nil }; return data
    }
    func text(_ field: Int) -> String? { data(field).flatMap { String(data: $0, encoding: .utf8) } }
    func messages(_ field: Int) -> [AppProto] {
        (fields[field] ?? []).compactMap { if case .bytes(let data) = $0 { return try? Self(data) }; return nil }
    }
    static func varint(_ value: UInt64) -> Data {
        var value = value, data = Data()
        repeat { let byte = UInt8(value & 127); value >>= 7; data.append(byte | (value == 0 ? 0 : 128)) } while value > 0
        return data
    }
    static func integer(_ field: Int, _ value: Int) -> Data {
        guard value > 0 else { return Data() }
        return varint(UInt64(field << 3)) + varint(UInt64(value))
    }
    static func bytes(_ field: Int, _ data: Data) -> Data { varint(UInt64(field << 3 | 2)) + varint(UInt64(data.count)) + data }
    static func string(_ field: Int, _ value: String?) -> Data {
        guard let value, !value.isEmpty else { return Data() }; return bytes(field, Data(value.utf8))
    }
    static func frame(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        return Data([0, UInt8(length >> 24), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)]) + payload
    }
    static func unframe(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 5 else { throw Failure.malformed }
        let length = bytes[1...4].reduce(0) { ($0 << 8) | Int($1) }
        guard length == bytes.count - 5, length <= 16 * 1024 * 1024 else { throw Failure.malformed }
        let payload = Data(bytes.dropFirst(5))
        if bytes[0] == 0 { return payload }
        guard bytes[0] == 1 else { throw Failure.malformed }
        return try gunzip(payload)
    }
    static func gunzip(_ data: Data) throws -> Data {
        let input = [UInt8](data)
        guard input.count >= 18, input[0] == 31, input[1] == 139, input[2] == 8 else { throw Failure.malformed }
        let flags = input[3]; var start = 10
        guard flags & 224 == 0 else { throw Failure.malformed }
        if flags & 4 != 0 {
            guard start + 2 <= input.count - 8 else { throw Failure.malformed }
            let extra = Int(input[start]) | Int(input[start + 1]) << 8; start += 2 + extra
        }
        for flag in [UInt8(8), UInt8(16)] where flags & flag != 0 {
            while start < input.count - 8 && input[start] != 0 { start += 1 }; start += 1
        }
        if flags & 2 != 0 { start += 2 }
        guard start < input.count - 8 else { throw Failure.malformed }
        let raw = Data(input[start..<(input.count - 8)])
        return try raw.withUnsafeBytes { source in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 16_384)
            defer { buffer.deallocate() }
            var stream = compression_stream(dst_ptr: buffer, dst_size: 0,
                src_ptr: source.bindMemory(to: UInt8.self).baseAddress!, src_size: 0, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else { throw Failure.malformed }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!
            stream.src_size = raw.count
            var output = Data()
            while true {
                stream.dst_ptr = buffer; stream.dst_size = 16_384
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status != COMPRESSION_STATUS_ERROR else { throw Failure.malformed }
                let count = 16_384 - stream.dst_size
                guard output.count + count <= 16 * 1024 * 1024 else { throw Failure.oversized }
                output.append(buffer, count: count)
                if status == COMPRESSION_STATUS_END {
                    let trailer = input.count - 8
                    func littleEndian(_ offset: Int) -> UInt32 {
                        (0..<4).reduce(UInt32(0)) { $0 | UInt32(input[offset + $1]) << ($1 * 8) }
                    }
                    var crc: UInt32 = 0xffffffff
                    for byte in output {
                        crc ^= UInt32(byte)
                        for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320) }
                    }
                    guard stream.src_size == 0, UInt32(output.count) == littleEndian(trailer + 4),
                          ~crc == littleEndian(trailer) else { throw Failure.malformed }
                    return output
                }
                guard count > 0 else { throw Failure.malformed }
            }
        }
    }
}

