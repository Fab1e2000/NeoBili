import Foundation
#if canImport(Network)
import Network
#endif

/// One coherent read of the local connection, shared by query and header builders.
/// Unknown/offline connections must never be reported as Wi-Fi.
struct AppNetworkMetadataSnapshot: Equatable, Sendable {
    enum Connection: Equatable, Sendable {
        case unknown, wifi, mobile
    }

    let connection: Connection

    /// BFCReachability's confirmed mapping: Wi-Fi / cellular / everything else.
    var queryNetwork: String {
        switch connection {
        case .wifi: return "wifi"
        case .mobile: return "mobile"
        case .unknown: return ""
        }
    }

    var headers: [String: String] {
        let kind: UInt8
        switch connection {
        case .wifi: kind = 1
        case .mobile: kind = 2
        case .unknown: return [:]
        }
        // Metadata Network field 1 is the connection type. Field 5 is measured
        // network-quality data, whose producer is not implemented: never copy a
        // captured score, bandwidth or timestamp into a new request.
        return ["x-bili-network-bin": Data([0x08, kind]).base64EncodedString()]
    }
}

/// Nonblocking, process-local path monitoring. No location, SSID or carrier access.
/// The first request may precede the first path callback and truthfully omit the
/// binary header. Regression instances never start a system monitor.
final class AppNetworkMetadata: @unchecked Sendable {
    static let shared = AppNetworkMetadata(monitoring: !AppNetwork.isRegression)

    private let lock = NSLock()
    private var current = AppNetworkMetadataSnapshot(connection: .unknown)
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    init(monitoring: Bool = false) {
        #if canImport(Network)
        if monitoring {
            let monitor = NWPathMonitor()
            self.monitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                self?.update(isSatisfied: path.status == .satisfied,
                             usesWiFi: path.usesInterfaceType(.wifi),
                             usesCellular: path.usesInterfaceType(.cellular))
            }
            monitor.start(queue: DispatchQueue(label: "NeoBili.NetworkMetadata"))
        }
        #endif
    }

    deinit {
        #if canImport(Network)
        monitor?.cancel()
        #endif
    }

    func snapshot() -> AppNetworkMetadataSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Also provides deterministic path injection for regression tests. Cost and
    /// constrained-path flags are not substitutes for the actual interface type.
    func update(isSatisfied: Bool, usesWiFi: Bool, usesCellular: Bool) {
        let connection: AppNetworkMetadataSnapshot.Connection
        if !isSatisfied { connection = .unknown }
        else if usesWiFi { connection = .wifi }
        else if usesCellular { connection = .mobile }
        else { connection = .unknown }
        lock.lock()
        current = AppNetworkMetadataSnapshot(connection: connection)
        lock.unlock()
    }
}
