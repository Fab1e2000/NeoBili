import CryptoKit
import Foundation
import Security

/// B 站网页端密码登录的加密环节：用 `passport/x/passport-login/web/key` 返回的
/// PEM 公钥，对 `hash + md5(密码)`（hash 是同一次响应里的 16 位盐）做
/// PKCS#1 v1.5 加密后转 base64，与网页端行为一致。
enum PasswordCipher {
    enum CipherError: LocalizedError, Equatable {
        case malformedPublicKey
        case encryptionFailed

        var errorDescription: String? {
            switch self {
            case .malformedPublicKey: return "登录公钥格式异常"
            case .encryptionFailed: return "密码加密失败"
            }
        }
    }

    static func encryptedPassword(_ password: String, salt hash: String, publicKeyPEM: String) throws -> String {
        let key = try secKey(fromPEM: publicKeyPEM)
        // 网页端先取密码的 md5 十六进制串，再拼上本次的 hash 一起加密。
        let message = hash + md5Hex(password)
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            Data(message.utf8) as CFData,
            &error
        ) as Data? else {
            throw CipherError.encryptionFailed
        }
        return encrypted.base64EncodedString()
    }

    /// PEM(SPKI) → DER。Security 框架的 `SecKeyCreateWithData` 只认 PKCS#1 裸
    /// 公钥，而 B 站返回的是带头部的 SPKI，需要先定位 rsaEncryption OID，
    /// 剥掉 SPKI 头。两种格式都尝试，兼容服务端未来直接下发裸公钥。
    private static func secKey(fromPEM pem: String) throws -> SecKey {
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .filter { !$0.isNewline }
        guard let der = Data(base64Encoded: base64) else {
            throw CipherError.malformedPublicKey
        }

        let pkcs1 = stripSPKIHeaderIfPresent(der) ?? der
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else {
            throw CipherError.malformedPublicKey
        }
        return key
    }

    /// SPKI 结构固定为 `SEQUENCE { SEQUENCE { OID rsaEncryption, NULL }, BIT STRING { PKCS#1 } }`。
    /// 找到 OID 标记后跳过 BIT STRING 的 tag、长度和未用位数占位字节，剩下的就是 PKCS#1。
    private static func stripSPKIHeaderIfPresent(_ der: Data) -> Data? {
        // 06 09 2A 86 48 86 F7 0D 01 01 01 = OID rsaEncryption, 05 00 = NULL
        let marker: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        guard let markerRange = der.firstRange(of: Data(marker)) else { return nil }
        var start = markerRange.upperBound
        let bytes = [UInt8](der[start...].prefix(5))
        // BIT STRING：03 82 <len_hi> <len_lo> 00 —— 最后一个 0x00 是未用位数。
        guard bytes.count >= 5, bytes[0] == 0x03 else { return nil }
        start += 5
        guard start < der.count, der[start] == 0x30 else { return nil }
        return der.subdata(in: start..<der.count)
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
