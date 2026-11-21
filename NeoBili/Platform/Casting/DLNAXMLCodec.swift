#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

enum DLNAXMLCodec {
    static let avTransportServiceType = "urn:schemas-upnp-org:service:AVTransport:1"
    static let renderingControlServiceType = "urn:schemas-upnp-org:service:RenderingControl:1"

    struct SSDPResponse: Hashable, Sendable {
        let location: URL
        let usn: String?
        let st: String?
        let server: String?
    }

    /// 解析单条 SSDP M-SEARCH 响应报文，提取 LOCATION / USN / ST / SERVER。
    static func parseSSDPResponse(_ raw: String) -> SSDPResponse? {
        let lines = raw.components(separatedBy: .newlines)
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        guard let locationString = headers["location"],
              let location = URL(string: locationString),
              let scheme = location.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return SSDPResponse(
            location: location,
            usn: headers["usn"],
            st: headers["st"],
            server: headers["server"]
        )
    }

    /// 解析 UPnP Device Description XML，提取设备信息和 AVTransport / RenderingControl 控制地址。
    static func parseDeviceDescription(_ data: Data, location: URL) throws -> CastDevice {
        let delegate = DeviceXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw CastError.unsupportedDevice
        }
        let baseURL = delegate.urlBase.flatMap(URL.init(string:)) ?? location
        guard let avPath = delegate.avTransportControlURL,
              let avURL = resolveControlURL(baseURL: baseURL, controlPath: avPath) else {
            throw CastError.unsupportedDevice
        }
        let renderingURL = delegate.renderingControlURL.flatMap {
            resolveControlURL(baseURL: baseURL, controlPath: $0)
        }
        let name = delegate.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false ? name! : nil) ?? location.host ?? location.absoluteString
        let id = delegate.udn?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID = (id?.isEmpty == false ? id! : nil) ?? location.absoluteString
        return CastDevice(
            id: resolvedID,
            name: resolvedName,
            manufacturer: delegate.manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: delegate.modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location,
            avTransportControlURL: avURL,
            renderingControlURL: renderingURL
        )
    }

    /// 规范化 UPnP controlURL（兼容绝对 URL、相对路径、以及旧版乐播等缺少前导斜杠的路径）。
    static func resolveControlURL(baseURL: URL, controlPath: String) -> URL? {
        let trimmed = controlPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absolute
        }
        // 取 scheme://host[:port] 作为根地址，避免 baseURL 本身带 /desc.xml 时拼错路径。
        var rootComponents = URLComponents()
        rootComponents.scheme = baseURL.scheme
        rootComponents.host = baseURL.host
        rootComponents.port = baseURL.port
        guard let rootURL = rootComponents.url else { return nil }

        let normalizedPath: String
        if trimmed.hasPrefix("/") {
            normalizedPath = trimmed
        } else {
            // 兼容相对路径与旧版乐播控制路径：统一挂到根路径下（除非明确是 ./ 或 ../ 相对路径）。
            if trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
                return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            }
            normalizedPath = "/" + trimmed
        }
        return URL(string: normalizedPath, relativeTo: rootURL)?.absoluteURL
    }

    static func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }

    static func buildDIDLMetadata(title: String, mediaURL: URL, mimeType: String, isLive: Bool) -> String {
        let safeTitle = escapeXML(title.isEmpty ? "NeoBili" : title)
        let safeURL = escapeXML(mediaURL.absoluteString)
        let safeMime = escapeXML(mimeType)
        let dlnaFlags = isLive ? "DLNA.ORG_OP=00;DLNA.ORG_CI=0" : "DLNA.ORG_OP=01;DLNA.ORG_CI=0"
        let protocolInfo = "http-get:*:\(safeMime):\(dlnaFlags)"
        return """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">\
        <item id="0" parentID="-1" restricted="1">\
        <dc:title>\(safeTitle)</dc:title>\
        <upnp:class>object.item.videoItem</upnp:class>\
        <res protocolInfo="\(protocolInfo)">\(safeURL)</res>\
        </item>\
        </DIDL-Lite>
        """
    }

    static func soapEnvelope(serviceType: String, action: String, arguments: [(String, String)]) -> String {
        let bodyArgs = arguments.map { key, value in
            "<\(key)>\(value)</\(key)>"
        }.joined()
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body>
        <u:\(action) xmlns:u="\(serviceType)">\(bodyArgs)</u:\(action)>
        </s:Body>
        </s:Envelope>
        """
    }

    static func setAVTransportURIEnvelope(mediaURL: URL, title: String, mimeType: String, isLive: Bool) -> String {
        let didl = buildDIDLMetadata(title: title, mediaURL: mediaURL, mimeType: mimeType, isLive: isLive)
        return soapEnvelope(
            serviceType: avTransportServiceType,
            action: "SetAVTransportURI",
            arguments: [
                ("InstanceID", "0"),
                ("CurrentURI", escapeXML(mediaURL.absoluteString)),
                ("CurrentURIMetaData", escapeXML(didl))
            ]
        )
    }

    static func playEnvelope() -> String {
        soapEnvelope(
            serviceType: avTransportServiceType,
            action: "Play",
            arguments: [("InstanceID", "0"), ("Speed", "1")]
        )
    }

    static func pauseEnvelope() -> String {
        soapEnvelope(
            serviceType: avTransportServiceType,
            action: "Pause",
            arguments: [("InstanceID", "0")]
        )
    }

    static func stopEnvelope() -> String {
        soapEnvelope(
            serviceType: avTransportServiceType,
            action: "Stop",
            arguments: [("InstanceID", "0")]
        )
    }

    static func seekEnvelope(seconds: TimeInterval) -> String {
        soapEnvelope(
            serviceType: avTransportServiceType,
            action: "Seek",
            arguments: [
                ("InstanceID", "0"),
                ("Unit", "REL_TIME"),
                ("Target", formatTime(seconds))
            ]
        )
    }

    static func getPositionInfoEnvelope() -> String {
        soapEnvelope(
            serviceType: avTransportServiceType,
            action: "GetPositionInfo",
            arguments: [("InstanceID", "0")]
        )
    }

    static func getTransportInfoEnvelope() -> String {
        soapEnvelope(
            serviceType: avTransportServiceType,
            action: "GetTransportInfo",
            arguments: [("InstanceID", "0")]
        )
    }

    static func getVolumeEnvelope() -> String {
        soapEnvelope(
            serviceType: renderingControlServiceType,
            action: "GetVolume",
            arguments: [("InstanceID", "0"), ("Channel", "Master")]
        )
    }

    static func setVolumeEnvelope(level: Int) -> String {
        let clamped = max(0, min(100, level))
        return soapEnvelope(
            serviceType: renderingControlServiceType,
            action: "SetVolume",
            arguments: [
                ("InstanceID", "0"),
                ("Channel", "Master"),
                ("DesiredVolume", String(clamped))
            ]
        )
    }

    /// 格式化为 UPnP REL_TIME（HH:MM:SS）。
    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// 解析 UPnP 时间字符串（支持 HH:MM:SS 和 HH:MM:SS.fff）。
    static func parseTime(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "NOT_IMPLEMENTED" else { return nil }
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]),
              h.isFinite, m.isFinite, s.isFinite else {
            return nil
        }
        return max(0, h * 3600 + m * 60 + s)
    }

    static func parseSOAPValues(_ data: Data) -> [String: String] {
        let delegate = FlatXMLValuesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.values
    }

    static func parsePositionInfo(_ data: Data) -> CastPlaybackPosition {
        let values = parseSOAPValues(data)
        let position = values["RelTime"].flatMap(parseTime) ?? 0
        let duration = values["TrackDuration"].flatMap(parseTime) ?? 0
        return CastPlaybackPosition(position: position, duration: duration)
    }

    static func parseTransportState(_ data: Data) -> CastTransportState {
        let values = parseSOAPValues(data)
        switch values["CurrentTransportState"]?.uppercased() {
        case "PLAYING": return .playing
        case "PAUSED_PLAYBACK", "PAUSED_RECORDING": return .paused
        case "TRANSITIONING": return .transitioning
        case "STOPPED", "NO_MEDIA_PRESENT": return .stopped
        default: return .unknown
        }
    }

    static func parseVolume(_ data: Data) -> Int? {
        let values = parseSOAPValues(data)
        guard let raw = values["CurrentVolume"], let value = Int(raw) else { return nil }
        return max(0, min(100, value))
    }

    static func parseSOAPFault(_ data: Data) -> (code: String?, message: String)? {
        let values = parseSOAPValues(data)
        if let desc = values["errorDescription"], !desc.isEmpty {
            return (values["errorCode"], desc)
        }
        if let fault = values["faultstring"], !fault.isEmpty {
            return (values["faultcode"], fault)
        }
        return nil
    }
}

private final class DeviceXMLParserDelegate: NSObject, XMLParserDelegate {
    var urlBase: String?
    var friendlyName: String?
    var manufacturer: String?
    var modelName: String?
    var udn: String?
    var avTransportControlURL: String?
    var renderingControlURL: String?

    private var elementStack: [String] = []
    private var currentText = ""
    private var inService = false
    private var currentServiceType: String?
    private var currentControlURL: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = stripNamespace(elementName)
        elementStack.append(local)
        currentText = ""
        if local == "service" {
            inService = true
            currentServiceType = nil
            currentControlURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let local = stripNamespace(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inService {
            switch local {
            case "serviceType":
                currentServiceType = text
            case "controlURL":
                currentControlURL = text
            case "service":
                if let type = currentServiceType, let control = currentControlURL, !control.isEmpty {
                    if type.localizedCaseInsensitiveContains("AVTransport") && avTransportControlURL == nil {
                        avTransportControlURL = control
                    } else if type.localizedCaseInsensitiveContains("RenderingControl") && renderingControlURL == nil {
                        renderingControlURL = control
                    }
                }
                inService = false
            default:
                break
            }
        } else if !text.isEmpty {
            switch local {
            case "URLBase" where urlBase == nil:
                urlBase = text
            case "friendlyName" where friendlyName == nil:
                friendlyName = text
            case "manufacturer" where manufacturer == nil:
                manufacturer = text
            case "modelName" where modelName == nil:
                modelName = text
            case "UDN" where udn == nil:
                udn = text
            default:
                break
            }
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        currentText = ""
    }

    private func stripNamespace(_ name: String) -> String {
        if let colon = name.lastIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }
}

private final class FlatXMLValuesDelegate: NSObject, XMLParserDelegate {
    var values: [String: String] = [:]
    private var currentName: String?
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if let colon = elementName.lastIndex(of: ":") {
            currentName = String(elementName[elementName.index(after: colon)...])
        } else {
            currentName = elementName
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let local: String
        if let colon = elementName.lastIndex(of: ":") {
            local = String(elementName[elementName.index(after: colon)...])
        } else {
            local = elementName
        }
        if currentName == local {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                values[local] = trimmed
            }
        }
        currentName = nil
        currentText = ""
    }
}
