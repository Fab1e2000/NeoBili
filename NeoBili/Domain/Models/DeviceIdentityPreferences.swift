import Foundation

public enum DeviceIdentityPreferences {
    public static let customKey = "neobili.appBuvid.custom"
    public static func normalizedCustomBuvid(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(value.count), value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return value
    }
}
