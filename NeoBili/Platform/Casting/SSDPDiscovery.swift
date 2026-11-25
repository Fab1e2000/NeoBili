import NeoBiliDomain
import Darwin
import Foundation

enum LocalNetworkAddress {
    /// 返回当前设备的局域网 IPv4 地址（优先 Wi-Fi `en0`，其次其他活跃以太网/桥接网卡）。
    static func lanIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: String?
        var fallback: String?

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
                  (flags & IFF_LOOPBACK) == 0,
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ipBytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let ip = String(decoding: ipBytes, as: UTF8.self)
            // 跳过 link-local (169.254.x.x)
            guard !ip.hasPrefix("169.254.") else { continue }

            if name == "en0" {
                preferred = ip
                break
            } else if name.hasPrefix("en") || name.hasPrefix("bridge") {
                if fallback == nil { fallback = ip }
            }
        }
        return preferred ?? fallback
    }
}

enum SSDPDiscovery {
    private static let multicastHost = "239.255.255.250"
    private static let multicastPort: UInt16 = 1900

    private static let searchTargets = [
        "urn:schemas-upnp-org:service:AVTransport:1",
        "urn:schemas-upnp-org:device:MediaRenderer:1"
    ]

    /// 通过 UDP SSDP M-SEARCH 发现局域网内支持投屏的设备描述 URL 列表。
    static func discoverLocations(timeout: TimeInterval = 3.0) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            try discoverSync(timeout: max(0.5, min(timeout, 10.0)))
        }.value
    }

    private static func discoverSync(timeout: TimeInterval) throws -> [URL] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw CastError.localNetworkUnavailable
        }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        if let lanIP = LocalNetworkAddress.lanIPv4Address() {
            var ifaceAddr = in_addr()
            if inet_pton(AF_INET, lanIP, &ifaceAddr) == 1 {
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &ifaceAddr, socklen_t(MemoryLayout<in_addr>.size))
            }
        }

        var localAddr = sockaddr_in()
        localAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_port = 0
        localAddr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw CastError.localNetworkUnavailable
        }

        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = multicastPort.bigEndian
        inet_pton(AF_INET, multicastHost, &destAddr.sin_addr)

        let mx = max(1, min(3, Int(timeout.rounded(.down))))
        var sentAny = sendMulticastSearch(fd: fd, destAddr: &destAddr, mx: mx)

        var seen = Set<URL>()
        var results: [URL] = []
        let deadline = Date().addingTimeInterval(timeout)
        // 若多播被系统拦截（常见于无 multicast 权限的自签真机），立即回退同网段单播；
        // 若多播已发出但前 0.6s 仍无设备响应，同样补发单播兜底。
        let unicastTriggerTime = sentAny ? Date().addingTimeInterval(min(0.6, timeout * 0.35)) : Date()
        var didSendUnicast = false
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            if Task.isCancelled { break }
            let now = Date()
            if !didSendUnicast, results.isEmpty, now >= unicastTriggerTime {
                didSendUnicast = true
                if sendUnicastSubnetSearch(fd: fd, mx: mx) {
                    sentAny = true
                }
            }
            let remaining = deadline.timeIntervalSince(now)
            if remaining <= 0 { break }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let waitMs = Int32(min(150, max(10, remaining * 1000)))
            let ready = poll(&pfd, 1, waitMs)
            if ready <= 0 { continue }
            guard (pfd.revents & Int16(POLLIN)) != 0 else { continue }

            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { continue }
            let payload = String(decoding: buffer[..<count], as: UTF8.self)
            if let response = DLNAXMLCodec.parseSSDPResponse(payload),
               seen.insert(response.location).inserted {
                results.append(response.location)
            }
        }

        if !sentAny && results.isEmpty {
            throw CastError.localNetworkUnavailable
        }

        return results
    }

    private static func makeSearchPacket(host: String, target: String, mx: Int) -> Data {
        let packet = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(host):\(multicastPort)",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(target)",
            "USER-AGENT: NeoBili/1.0 UPnP/1.1",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(packet.utf8)
    }

    private static func sendMulticastSearch(fd: Int32, destAddr: inout sockaddr_in, mx: Int) -> Bool {
        var sentAny = false
        for target in searchTargets {
            let data = makeSearchPacket(host: multicastHost, target: target, mx: mx)
            let sent = data.withUnsafeBytes { rawBuffer in
                withUnsafePointer(to: &destAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        sendto(fd, rawBuffer.baseAddress, rawBuffer.count, 0,
                               sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent > 0 { sentAny = true }
        }
        return sentAny
    }

    /// 针对未开通 multicast entitlement 的 iOS 自签真机：向当前 /24 局域网主机 1900 端口发单播 M-SEARCH。
    private static func sendUnicastSubnetSearch(fd: Int32, mx: Int) -> Bool {
        guard let lanIP = LocalNetworkAddress.lanIPv4Address() else { return false }
        let octets = lanIP.split(separator: ".")
        guard octets.count == 4, let selfHost = Int(octets[3]) else { return false }
        let prefix = "\(octets[0]).\(octets[1]).\(octets[2])."

        // 单播只发送核心 MediaRenderer 目标，控制总包数为 253 个（约 30 KiB），几十毫秒内完成。
        let payload = makeSearchPacket(host: multicastHost, target: "urn:schemas-upnp-org:device:MediaRenderer:1", mx: mx)
        var sentAny = false
        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = multicastPort.bigEndian

        for host in 1...254 where host != selfHost {
            if Task.isCancelled { break }
            let ip = "\(prefix)\(host)"
            guard inet_pton(AF_INET, ip, &destAddr.sin_addr) == 1 else { continue }
            let sent = payload.withUnsafeBytes { rawBuffer in
                withUnsafePointer(to: &destAddr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        sendto(fd, rawBuffer.baseAddress, rawBuffer.count, 0,
                               sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            if sent > 0 { sentAny = true }
        }
        return sentAny
    }
}
