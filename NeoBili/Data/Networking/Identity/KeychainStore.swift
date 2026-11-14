import Foundation
import Security
import Synchronization

/// Keychain 存取封装，用于登录凭据和服务端票据；普通设备偏好保存在 UserDefaults。
enum KeychainStore {
    private static let service = AppNetwork.isRegression ? "com.elsterlee.NeoBili.regression" : "com.elsterlee.NeoBili"

    /// 写入 `nil` 等价于删除该条目。
    static func set(_ value: String?, for key: String) {
        var query = baseQuery(for: key)
        if let value {
            let data = Data(value.utf8)
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status == errSecItemNotFound {
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                SecItemAdd(query as CFDictionary, nil)
            }
        } else {
            SecItemDelete(query as CFDictionary)
        }
    }

    static func string(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

/// Injectable credential storage. Each memory instance has independent lifetime and contents.
public struct CredentialStorage: Sendable {
    var read: @Sendable (String) -> String?
    var write: @Sendable (String?, String) -> Void

    public static let keychain = CredentialStorage(read: { KeychainStore.string(for: $0) },
                                            write: { KeychainStore.set($0, for: $1) })
    public static func memory() -> CredentialStorage {
        let values = Mutex<[String: String]>([:])
        return CredentialStorage(read: { key in values.withLock { $0[key] } },
                                 write: { value, key in values.withLock { $0[key] = value } })
    }
}
