import XCTest
import Security
import CommonCrypto
@testable import NeoBili

final class GuestRegistrationTests: XCTestCase {
    private func keys() throws -> (SecKey, String) {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 1024] as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let bytes = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        return (key, "-----BEGIN RSA PUBLIC KEY-----\n\(bytes.base64EncodedString())\n-----END RSA PUBLIC KEY-----")
    }

    func testGuestEncryptionRoundTripsOwnFactsWithCBCKeyAsIV() throws {
        let (privateKey, pem) = try keys(), key = Data("0123456789ABCDEF".utf8)
        let material = try AppGuestProtocol.material(buvid: "own", vendorID: "own-vendor", firstRunMilliseconds: 1234567)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: material) as? [String: String])
        XCTAssertEqual(object, ["Buvid":"own", "IDFV":"own-vendor", "DeviceType":"ios", "fts":"1234567"])
        let fields = try AppGuestProtocol.encrypt(material: material, publicKey: pem, key: key)
        let rsa = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(fields["dt"])))
        let unwrapped = try XCTUnwrap(SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, rsa as CFData, nil) as Data?)
        XCTAssertEqual(unwrapped, key) // no RSA response hash prefix, no hex of key.
        let hex = try XCTUnwrap(fields["device_info"])
        XCTAssertEqual(hex, hex.lowercased())
        let chars = Array(hex)
        let cipher = Data(try stride(from: 0, to: chars.count, by: 2).map { try XCTUnwrap(UInt8(String(chars[$0...($0+1)]), radix: 16)) })
        var plain = Data(count: cipher.count), count = 0
        let status = plain.withUnsafeMutableBytes { out in key.withUnsafeBytes { k in cipher.withUnsafeBytes { c in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    k.baseAddress, key.count, k.baseAddress, c.baseAddress, cipher.count, out.baseAddress, out.count, &count)
        } } }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        plain.removeSubrange(count..<plain.count)
        XCTAssertEqual(plain, material)
    }

    func testSuccessfulGuestSurvivesNewServiceAndDoesNotUseLoginCredentials() async throws {
        let (_, pem) = try keys(), store = CredentialStorage.memory(), recorder = GuestRequestRecorder()
        let service = AppGuestRegistration(credentials: store, transport: { request in
            await recorder.add(request)
            let response: [String: Any] = request.httpMethod == "GET" ? ["key": pem, "hash": "not-prepended"] : ["guest_id": "-3"]
            return (try JSONSerialization.data(withJSONObject: ["code": 0, "data": response]),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json;charset=UTF-8"])!)
        }, vendorIdentifier: { "own-vendor" }, clock: { 1000 })
        let id = await service.load(buvid: "own", headers: ["buvid":"own"])
        XCTAssertEqual(id, -3) // researched acceptance rejects only 0/-2.
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/x/passport-login/web/key")
        XCTAssertEqual(requests[1].url?.path, "/x/passport-user/guest/reg")
        let body = try XCTUnwrap(String(data: XCTUnwrap(requests[1].httpBody), encoding: .utf8))
        XCTAssertTrue(body.contains("sdk_ver=0.1.15"))
        XCTAssertFalse(body.contains("access_key"))
        let restored = AppGuestRegistration(credentials: store, transport: { _ in XCTFail("cached guest must not register"); throw URLError(.badURL) })
        let persisted = await restored.load(buvid: "own", headers: [:])
        XCTAssertEqual(persisted, -3)
        XCTAssertEqual(store.read(AppGuestRegistration.firstRunKey), "1000000")
    }

    func testFailedRegistrationDoesNotPersistAndNextActivationRetries() async throws {
        let store = CredentialStorage.memory(), recorder = GuestRequestRecorder()
        let service = AppGuestRegistration(credentials: store, transport: { request in
            await recorder.add(request)
            return (Data(#"{"code":-1,"data":{"key":"invalid"}}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!)
        }, vendorIdentifier: { nil }, clock: { 1234 })
        let first = await service.load(buvid: "own", headers: [:])
        let second = await service.load(buvid: "own", headers: [:])
        XCTAssertNil(first); XCTAssertNil(second)
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(store.read(AppGuestRegistration.storageKey))
        XCTAssertFalse(AppGuestRegistration.isValid(0)); XCTAssertFalse(AppGuestRegistration.isValid(-2))
    }
}

private actor GuestRequestRecorder {
    var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
}
