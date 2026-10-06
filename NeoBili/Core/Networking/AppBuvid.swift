import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Official 8.89 local branch: prefix plus three characters plus 32 UUID digits.
/// Existing persisted identities are never regenerated during an upgrade.
enum AppBuvid {
    static func generate(idfa: String? = nil, idfv: String?) -> String? {
        func normalized(_ value: String?) -> String? {
            guard let value else { return nil }
            let digits = value.replacingOccurrences(of: "-", with: "").uppercased()
            guard digits.count == 32, digits.allSatisfy(\.isHexDigit),
                  digits != String(repeating: "0", count: 32) else { return nil }
            return digits
        }
        let advertising = normalized(idfa)
        guard let digits = advertising ?? normalized(idfv) else { return nil }
        let chars = Array(digits)
        return "\(advertising == nil ? "Y" : "Z")\(chars[2])\(chars[12])\(chars[22])\(digits)"
    }

    static func vendorIdentifier() async -> String? {
        #if canImport(UIKit)
        return await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        #else
        return nil
        #endif
    }
}
