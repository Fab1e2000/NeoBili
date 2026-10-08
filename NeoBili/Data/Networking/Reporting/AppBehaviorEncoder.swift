import Foundation
import Compression

/// Wire encoding is independent of the durable click queue and its delivery policy.
enum AppBehaviorEncoder {
    static func clickPayload(_ event: RecommendationClick, uploadTime: Int) -> Data {
        payload(context: event.context, timestamp: event.timestamp, fields: event.fields,
                name: RecommendationClick.event, category: 2, player: nil, uploadTime: uploadTime)
    }

    static func payload(context: AppDeviceSnapshot, timestamp: Int, fields: [String: String],
                        name: String, category: Int, player: Data?, uploadTime: Int) -> Data {
        func map(_ field: Int, _ values: [String: String]) -> Data {
            values.sorted { $0.key < $1.key }.reduce(Data()) { result, pair in
                result + AppProto.bytes(field, AppProto.string(1, pair.key) + AppProto.bytes(2, Data(pair.value.utf8)))
            }
        }
        var device = AppProto.integer(1, 1) + AppProto.integer(2, 1)
        device += AppProto.string(3, context.buvid) + AppProto.string(4, "pink_overseas")
        device += AppProto.string(5, "Apple") + AppProto.string(6, context.buvid)
        device += AppProto.string(7, context.model) + AppProto.string(15, context.requestSession)
        device += AppProto.string(14, context.fingerprint)
        let base = AppProto.string(5, context.version) + AppProto.string(6, context.build)
        // Unknown base/fingerprint fields remain absent; copying a captured user's
        // fingerprint would incorrectly associate other devices with that user.
        var result = AppProto.string(1, name) + AppProto.bytes(2, device) + AppProto.bytes(3, base)
        result += AppProto.string(4, context.mid.map(String.init)) + AppProto.integer(5, timestamp)
        result += AppProto.string(6, RecommendationClick.logID) + AppProto.integer(9, category)
        if let serial = context.eventSerial { result += AppProto.integer(8, serial) }
        if category == 2 { result += AppProto.bytes(11, Data()) }
        if category == 3 {
            let content = AppProto.string(1, name) + map(2, fields)
            result += AppProto.bytes(12, AppProto.bytes(1, content))
        }
        if let player { result += AppProto.bytes(17, player) }
        result += map(13, fields) + AppProto.integer(15, timestamp) + AppProto.integer(16, uploadTime)
        result += map(18, ["start_session_id": context.startSession, "polaris_action_id": ""])
        return result
    }

    static func behaviorBody(_ events: [AppBehaviorEvent], uploadTime: Int) throws -> Data {
        let data = events.reduce(Data()) { result, event in
            let metadata = [("appId", "1"), ("platform", "1"), ("eventId", event.name),
                            ("logId", RecommendationClick.logID), ("appVersionCode", event.context.build)]
            return result + RecommendationRecordIO.encode(metadata: metadata, payload:
                payload(context: event.context, timestamp: event.timestamp, fields: event.fields,
                        name: event.name, category: event.category, player: event.player, uploadTime: uploadTime))
        }
        return try RecommendationRecordIO.gzip(data)
    }

    static func clickBody(_ event: RecommendationClick, uploadTime: Int) throws -> Data {
        let context = event.context
        let metadata = [("appId", "1"), ("platform", "1"), ("eventId", RecommendationClick.event),
                        ("logId", RecommendationClick.logID), ("appVersionCode", context.build)]
        return try RecommendationRecordIO.gzip(RecommendationRecordIO.encode(
            metadata: metadata, payload: clickPayload(event, uploadTime: uploadTime)))
    }
}

/// Apache brpc RecordIO framing observed in the official binary log batches.
enum RecommendationRecordIO {
    static func word(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
    static func checksum(_ value: UInt32) -> UInt8 {
        var crc: UInt8 = 0
        for shift in stride(from: 0, through: 24, by: 8) {
            var byte = (crc ^ UInt8((value >> shift) & 255)) ^ 255
            for _ in 0..<8 { byte = (byte >> 1) ^ (byte & 1 == 0 ? 0 : 0xb2) }
            crc = byte ^ 255
        }
        return crc
    }
    static func encode(metadata: [(String, String)], payload: Data) -> Data {
        var body = Data()
        for (index, pair) in metadata.enumerated() {
            let name = Data(pair.0.utf8), value = Data(pair.1.utf8)
            precondition(name.count <= 255 && value.count < 1 << 31)
            body.append(UInt8(name.count)); body += name
            body += word(UInt32(value.count) | (index + 1 < metadata.count ? 0x80000000 : 0))
            body += value
        }
        body += payload
        precondition(body.count < 1 << 31)
        let size = UInt32(body.count) | (metadata.isEmpty ? 0 : 0x80000000)
        return Data("RDIO".utf8) + word(size) + Data([checksum(size)]) + body
    }
    static func gzip(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 1024 * 1024 else { throw AppProto.Failure.oversized }
        return try data.withUnsafeBytes { source in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 16_384)
            defer { buffer.deallocate() }
            var stream = compression_stream(dst_ptr: buffer, dst_size: 0,
                src_ptr: source.bindMemory(to: UInt8.self).baseAddress!, src_size: 0, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
                throw AppProto.Failure.malformed
            }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = source.bindMemory(to: UInt8.self).baseAddress!; stream.src_size = data.count
            var output = Data([31, 139, 8, 0, 0, 0, 0, 0, 0, 3])
            while true {
                stream.dst_ptr = buffer; stream.dst_size = 16_384
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status != COMPRESSION_STATUS_ERROR, output.count < 2 * 1024 * 1024 else { throw AppProto.Failure.malformed }
                let count = 16_384 - stream.dst_size
                output.append(buffer, count: count)
                if status == COMPRESSION_STATUS_END { break }
                guard count > 0 else { throw AppProto.Failure.malformed }
            }
            var crc: UInt32 = 0xffffffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xedb88320) }
            }
            for value in [~crc, UInt32(data.count)] {
                for shift in stride(from: 0, through: 24, by: 8) { output.append(UInt8((value >> shift) & 255)) }
            }
            return output
        }
    }
}
