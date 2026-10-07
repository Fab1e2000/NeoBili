import XCTest
import Security
import CommonCrypto
@testable import NeoBili

final class DeviceRegistrationTests: XCTestCase {
    func testFingerprintWrapsHexKeyAndEncryptsExactProtobufWithECBPadding() throws {
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 1024
        ] as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey,nil) as Data?)
        let pem = "-----BEGIN RSA PUBLIC KEY-----\n\(der.base64EncodedString())\n-----END RSA PUBLIC KEY-----"
        let key = Data(1...16), material = AppProto.string(1,"ios") + AppProto.string(30,"own-local")
        let body = try IOSFingerprintProtocol.encryptedBody(material: material,key: key, publicKeyPEM: pem)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String:String])
        XCTAssertEqual(Set(values.keys), ["key","content"])
        let wrapped = try bytes(XCTUnwrap(values["key"])), encrypted = try bytes(XCTUnwrap(values["content"]))
        XCTAssertEqual(wrapped.count, 128)
        let secret = try XCTUnwrap(SecKeyCreateDecryptedData(privateKey,.rsaEncryptionPKCS1,wrapped as CFData,nil) as Data?)
        XCTAssertEqual(String(data: secret,encoding: .utf8), key.map { String(format:"%02x",$0) }.joined())
        var plain = Data(count: encrypted.count), count = 0
        let status = plain.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { k in encrypted.withUnsafeBytes { cipher in
                CCCrypt(CCOperation(kCCDecrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionECBMode|kCCOptionPKCS7Padding),
                    k.baseAddress,key.count,nil,cipher.baseAddress,encrypted.count,output.baseAddress,output.count,&count)
            } }
        }
        XCTAssertEqual(status,CCCryptorStatus(kCCSuccess))
        plain.removeSubrange(count..<plain.count)
        XCTAssertEqual(plain,material)
        XCTAssertThrowsError(try IOSFingerprintProtocol.encryptedBody(material: material,key: Data(repeating: 0,count: 16)))
    }

    func testRegistrationUsesRealResponsePersistsAndRetriesOnlyAfterCooldown() async throws {
        let credentials = CredentialStorage.memory(), recorder = RegistrationRecorder()
        let material = AppProto.string(1,"ios")
        let registration = AppDeviceRegistration(credentials: credentials,transport: { request in
            await recorder.append(request)
            return (Data(#"{"code":0,"data":{"bili_deviceId":"server-own"}}"#.utf8),
                HTTPURLResponse(url: request.url!,statusCode: 200,httpVersion: nil,headerFields: nil)!)
        },material: { _,_ in material },clock: { 1000 })
        let first = await registration.register(buvid:"local",mid: 1,headers: ["buvid":"local"])
        let second = await registration.register(buvid:"local",mid: 1,headers: [:])
        XCTAssertEqual(first,"server-own");XCTAssertEqual(second,first)
        let requests = await recorder.requests
        XCTAssertEqual(requests.count,1)
        XCTAssertEqual(requests.first?.url?.path,"/x/resource/fingerprint")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField:"Content-Type"),"text/plain")
        let query = URLComponents(url: requests.first!.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: query.map { ($0.name,$0.value ?? "") })
        XCTAssertEqual(params["mobi_app"], "iphone")
        XCTAssertEqual(params["build"], "91300100")
        XCTAssertEqual(params["platform"], "ios")
        XCTAssertFalse(params["sign"]?.isEmpty ?? true)
        XCTAssertNil(requests.first?.value(forHTTPHeaderField:"Cookie"))
        let restored = AppDeviceRegistration(credentials: credentials,transport: { _ in
            XCTFail("valid persisted registration should not request again");throw URLError(.badServerResponse)
        },clock: { 1001 })
        let restoredValue = await restored.register(buvid:"local",mid:2,headers:[:])
        XCTAssertEqual(restoredValue,first)
        let other = await restored.cachedID(buvid:"different")
        XCTAssertNil(other)
    }

    func testRejectedRegistrationNeverInventsDeviceID() async {
        let recorder = RegistrationRecorder()
        let registration = AppDeviceRegistration(credentials:.memory(),transport: { request in
            await recorder.append(request)
            return (Data(#"{"code":-400,"data":{"bili_deviceId":"rejected"}}"#.utf8),
                HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        },material: { _,_ in AppProto.string(1,"ios") },clock: { 1000 })
        let first = await registration.register(buvid:"local",mid:nil,headers:[:])
        let second = await registration.register(buvid:"local",mid:nil,headers:[:])
        XCTAssertNil(first);XCTAssertNil(second)
        let count = await recorder.requests.count
        XCTAssertEqual(count,1)
    }

    func testRSAParsesSPKILengthsAndRoundTripsBothKeySizes() throws {
        func tlv(_ tag: UInt8, _ body: Data) -> Data {
            let length: [UInt8] = body.count < 128 ? [UInt8(body.count)]
                : body.count < 256 ? [0x81, UInt8(body.count)]
                : [0x82, UInt8(body.count >> 8), UInt8(body.count & 255)]
            return Data([tag] + length) + body
        }
        for size in [1024, 2048] {
            let secret = try XCTUnwrap(SecKeyCreateRandomKey([
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: size
            ] as CFDictionary, nil))
            let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(secret))
            let raw = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
            let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 1, 1, 1, 5, 0])
            let spki = tlv(0x30, algorithm + tlv(0x03, Data([0]) + raw))
            XCTAssertEqual(try PasswordCipher.rsaPKCS1Data(spki), raw)
            XCTAssertEqual(try PasswordCipher.rsaPKCS1Data(raw), raw)
            let pem = "-----BEGIN PUBLIC KEY-----\n\(spki.base64EncodedString())\n-----END PUBLIC KEY-----"
            let message = Data("independent-rsa-fixture".utf8)
            let encrypted = try PasswordCipher.encryptRSA(message, publicKeyPEM: pem)
            XCTAssertEqual(encrypted.count, size / 8)
            XCTAssertEqual(SecKeyCreateDecryptedData(secret, .rsaEncryptionPKCS1, encrypted as CFData, nil) as Data?, message)
            XCTAssertThrowsError(try PasswordCipher.rsaPKCS1Data(spki.dropLast()))
            XCTAssertThrowsError(try PasswordCipher.rsaPKCS1Data(spki + Data([0])))
        }
        for malformed: Data in [Data(), Data([0x30, 0x80]), Data([0x30, 0x84, 255, 255, 255, 255])] {
            XCTAssertThrowsError(try PasswordCipher.rsaPKCS1Data(malformed))
        }
    }

    func testBundledFingerprintPublicKeyEncryptsWithoutSubstitution() throws {
        let body = try IOSFingerprintProtocol.encryptedBody(material: AppProto.string(1, "ios"), key: Data(1...16))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(try bytes(XCTUnwrap(values["key"])).count, 128)
        XCTAssertFalse(try XCTUnwrap(values["content"]).isEmpty)
    }

    private func bytes(_ hex: String) throws -> Data {
        var bytes = Data(), index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index,offsetBy:2)
            bytes.append(try XCTUnwrap(UInt8(hex[index..<next],radix:16)));index = next
        }
        return bytes
    }
}

private actor RegistrationRecorder {
    var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}
