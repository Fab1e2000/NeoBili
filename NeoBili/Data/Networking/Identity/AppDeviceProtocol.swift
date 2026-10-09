import Foundation

/// An event-time device snapshot, independent of any particular report model.
/// The Codable keys also preserve the existing persisted click queue format.
struct AppDeviceSnapshot: Codable, Sendable {
    let buvid: String
    let requestSession: String
    let startSession: String
    let mid: Int?
    /// Local-only login generation. Never sent to the server.
    let accountEpoch: String
    let model: String
    let version: String
    let build: String
    var fingerprint: String? = nil
    var eventSerial: Int? = nil
}

/// DeviceIdentity owns values/lifetimes; this layer encodes their wire representation.
enum AppDeviceProtocol {
    static let sessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))

    static func headers(buvid: String, sessionID: String = sessionID) -> [String: String] {
        ["User-Agent": AppClientIdentity.userAgent,
         "buvid": buvid, "session_id": sessionID, "env": "prod",
         "app-key": AppClientIdentity.mobiApp,
         "x-bili-trace-id": traceID(), "x-bili-locale-bin": AppDeviceLocale.header]
    }

    static func traceID() -> String {
        func hex(_ count: Int) -> String { (0..<count).map { _ in String(Int.random(in: 0..<16), radix: 16) }.joined() }
        return "\(hex(32)):\(hex(16)):0:0"
    }
}

/// Only confirmed locale fields, shared by all App requests.
enum AppDeviceLocale {
    static var header: String {
        func field(_ number: UInt8, _ bytes: Data) -> Data {
            precondition(bytes.count < 128)
            return Data([number << 3 | 2, UInt8(bytes.count)]) + bytes
        }
        let locale = field(1, Data("zh".utf8)) + field(2, Data("Hans".utf8)) + field(3, Data("CN".utf8))
        return (field(1, locale) + field(2, locale) + field(4, Data("Asia/Shanghai".utf8))).base64EncodedString()
    }
}
