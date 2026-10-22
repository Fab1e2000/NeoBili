import Foundation
import CryptoKit

/// Private resource is added only to the explicitly authorized local Debug artifact.
public enum CapturedDeviceDiagnostic {
    #if DEBUG && NEOBILI_CAPTURED_DEVICE_DIAGNOSTIC
    public static let isEnabled = true
    #else
    public static let isEnabled = false
    #endif
    public struct Configuration: Codable, Sendable {
        var buvid: String
        let guestID: String
        var generationSeedIDFV: String? = nil
        // Keep the previous comparison caches when varying only the guest identifier.
        var registrationScopeGuestID: String? = nil
        var parsedGuestID: Int64 { Int64(guestID)! }
    }
    public static let configuration: Configuration? = {
        guard isEnabled, let url = Bundle.main.url(forResource: "DeviceIdentityComparison", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }()

    static func decode(_ data: Data) -> Configuration? {
        guard var value = try? JSONDecoder().decode(Configuration.self, from: data),
              (16...128).contains(value.buvid.count),
              value.buvid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let guest = Int64(value.guestID), guest != 0, guest != -2 else { return nil }
        if let scope = value.registrationScopeGuestID {
            guard let guest = Int64(scope), guest != 0, guest != -2 else { return nil }
        }
        if let seed = value.generationSeedIDFV {
            guard let generated = AppBuvid.generate(idfv: seed), generated == value.buvid else { return nil }
            value.buvid = generated
        }
        return value
    }

    static func isolatedStorage(_ base: CredentialStorage, configuration: Configuration) -> CredentialStorage {
        let scopeGuestID = configuration.registrationScopeGuestID ?? configuration.guestID
        let digest = SHA256.hash(data: Data((configuration.buvid + "|" + scopeGuestID).utf8))
            .map { String(format: "%02x", $0) }.joined()
        let prefix = "neobili.diagnostic.capturedDevice.v1." + digest + "."
        return CredentialStorage(read: { base.read(prefix + $0) }, write: { base.write($0, prefix + $1) })
    }
}
