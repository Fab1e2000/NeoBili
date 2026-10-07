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
            case .malformedPublicKey: return String(localized: "登录公钥格式异常")
            case .encryptionFailed: return String(localized: "密码加密失败")
            }
        }
    }

    static func encryptedPassword(_ password: String, salt hash: String, publicKeyPEM: String) throws -> String {
        try encryptRSA(Data((hash + md5Hex(password)).utf8), publicKeyPEM: publicKeyPEM).base64EncodedString()
    }

    static func encryptRSA(_ message: Data, publicKeyPEM: String) throws -> Data {
        let key = try secKey(fromPEM: publicKeyPEM)
        // 网页端先取密码的 md5 十六进制串，再拼上本次的 hash 一起加密。
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            key,
            .rsaEncryptionPKCS1,
            message as CFData,
            &error
        ) as Data? else {
            throw CipherError.encryptionFailed
        }
        return encrypted
    }

    /// PEM(SPKI) → DER。Security 框架的 `SecKeyCreateWithData` 只认 PKCS#1 裸
    /// 公钥，而服务端可能返回带头部的 SPKI。按 ASN.1 结构校验 rsaEncryption OID
    /// 和长度后提取裸公钥；也接受直接下发的 PKCS#1，不依赖固定头长或密钥位数。
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

        let pkcs1 = try rsaPKCS1Data(der)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else {
            throw CipherError.malformedPublicKey
        }
        return key
    }

    /// Decode DER lengths instead of assuming a 2048-bit SPKI header size.
    /// Security derives the RSA key size from the extracted modulus.
    static func rsaPKCS1Data(_ der: Data) throws -> Data {
        var root = DERReader(bytes: Array(der))
        var sequence = DERReader(bytes: try root.read(tag: 0x30))
        guard root.isAtEnd else { throw CipherError.malformedPublicKey }
        if sequence.bytes.first == 0x02 { return der } // PKCS#1; Security validates the integers.
        var algorithm = DERReader(bytes: try sequence.read(tag: 0x30))
        let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        guard try algorithm.read(tag: 0x06) == rsaOID else { throw CipherError.malformedPublicKey }
        if !algorithm.isAtEnd {
            guard try algorithm.read(tag: 0x05).isEmpty else { throw CipherError.malformedPublicKey }
        }
        let bitString = try sequence.read(tag: 0x03)
        guard algorithm.isAtEnd, sequence.isAtEnd, bitString.first == 0,
              bitString.dropFirst().first == 0x30 else { throw CipherError.malformedPublicKey }
        return Data(bitString.dropFirst())
    }

    private struct DERReader {
        let bytes: [UInt8]
        var offset = 0
        var isAtEnd: Bool { offset == bytes.count }

        mutating func read(tag: UInt8) throws -> [UInt8] {
            guard bytes.count - offset >= 2, bytes[offset] == tag else { throw CipherError.malformedPublicKey }
            offset += 1
            let first = bytes[offset]; offset += 1
            var length = Int(first)
            if first & 0x80 != 0 {
                let count = Int(first & 0x7F)
                guard count > 0, count <= 4, count <= bytes.count - offset,
                      bytes[offset] != 0 else { throw CipherError.malformedPublicKey }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(bytes[offset]); offset += 1 }
                guard length >= 128 else { throw CipherError.malformedPublicKey }
            }
            guard length <= bytes.count - offset else { throw CipherError.malformedPublicKey }
            defer { offset += length }
            return Array(bytes[offset..<(offset + length)])
        }
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
