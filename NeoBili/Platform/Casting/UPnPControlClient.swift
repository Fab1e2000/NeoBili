import NeoBiliDomain
import Foundation

final class UPnPControlClient: Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 12
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    func fetchDeviceDescription(from location: URL) async throws -> CastDevice {
        var request = URLRequest(url: location)
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CastError.transportFailed(String(localized: "无法读取投屏设备描述信息"))
        }
        return try DLNAXMLCodec.parseDeviceDescription(data, location: location)
    }

    func setAVTransportURI(device: CastDevice, mediaURL: URL, title: String, mimeType: String, isLive: Bool) async throws {
        let body = DLNAXMLCodec.setAVTransportURIEnvelope(
            mediaURL: mediaURL,
            title: title,
            mimeType: mimeType,
            isLive: isLive
        )
        _ = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "SetAVTransportURI",
            body: body
        )
    }

    func play(device: CastDevice) async throws {
        _ = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "Play",
            body: DLNAXMLCodec.playEnvelope()
        )
    }

    func pause(device: CastDevice) async throws {
        _ = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "Pause",
            body: DLNAXMLCodec.pauseEnvelope()
        )
    }

    func stop(device: CastDevice) async throws {
        _ = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "Stop",
            body: DLNAXMLCodec.stopEnvelope()
        )
    }

    func seek(device: CastDevice, to seconds: TimeInterval) async throws {
        _ = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "Seek",
            body: DLNAXMLCodec.seekEnvelope(seconds: seconds)
        )
    }

    func positionInfo(device: CastDevice) async throws -> CastPlaybackPosition {
        let data = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "GetPositionInfo",
            body: DLNAXMLCodec.getPositionInfoEnvelope()
        )
        return DLNAXMLCodec.parsePositionInfo(data)
    }

    func transportState(device: CastDevice) async throws -> CastTransportState {
        let data = try await sendSOAP(
            to: device.avTransportControlURL,
            serviceType: DLNAXMLCodec.avTransportServiceType,
            action: "GetTransportInfo",
            body: DLNAXMLCodec.getTransportInfoEnvelope()
        )
        return DLNAXMLCodec.parseTransportState(data)
    }

    func volume(device: CastDevice) async throws -> Int {
        guard let controlURL = device.renderingControlURL else {
            throw CastError.transportFailed(String(localized: "当前设备不支持音量调节"))
        }
        let data = try await sendSOAP(
            to: controlURL,
            serviceType: DLNAXMLCodec.renderingControlServiceType,
            action: "GetVolume",
            body: DLNAXMLCodec.getVolumeEnvelope()
        )
        return DLNAXMLCodec.parseVolume(data) ?? 50
    }

    func setVolume(device: CastDevice, to level: Int) async throws {
        guard let controlURL = device.renderingControlURL else {
            throw CastError.transportFailed(String(localized: "当前设备不支持音量调节"))
        }
        _ = try await sendSOAP(
            to: controlURL,
            serviceType: DLNAXMLCodec.renderingControlServiceType,
            action: "SetVolume",
            body: DLNAXMLCodec.setVolumeEnvelope(level: level)
        )
    }

    private func sendSOAP(to url: URL, serviceType: String, action: String, body: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CastError.transportFailed(String(localized: "投屏设备无响应"))
        }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        if let fault = DLNAXMLCodec.parseSOAPFault(data) {
            throw CastError.soapFault(code: fault.code, message: fault.message)
        }
        throw CastError.transportFailed(String(localized: "投屏控制失败（HTTP \(http.statusCode)）"))
    }
}
