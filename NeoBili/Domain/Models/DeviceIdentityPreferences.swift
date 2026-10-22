import Foundation

public enum DeviceIdentityPreferences {
    public static let customKey = "neobili.appBuvid.custom"
    public static func normalizedCustomBuvid(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(value.count), value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return value
    }

    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case system, random
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .system: String(localized: "系统派生编号")
            case .random: String(localized: "随机编号")
            }
        }
    }
    public static let modeKey = "neobili.appBuvid.mode"



    // Legacy experiment artifacts use random only when no explicit preference exists.
    public static var randomExperimentEnabled: Bool {
        #if NEOBILI_RANDOM_BUVID_EXPERIMENT
        true
        #else
        false
        #endif
    }

}
