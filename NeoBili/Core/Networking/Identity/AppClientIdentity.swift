import Foundation
import Darwin

/// 与实测官方 iPhone 9.13.0 请求配套的身份；所有 App 通道共用。
/// build 是协议兼容版本，不是 NeoBili 自己的发布版本。
enum AppClientIdentity {
    static let mobiApp = "iphone"
    static let build = "91300100"
    static let version = "9.13.0"
    static let credentialScope = "ios-27eb53fc-v1"
    static let statistics = #"{"appId":1,"version":"9.13.0","abtest":"","platform":1}"#
    static let parameters = ["mobi_app": mobiApp, "build": build, "platform": "ios", "device": "phone"]

    // Hardware model and OS identity are fixed for the lifetime of this process.
    static let deviceName: String = {
        let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? systemValue("hw.machine")
        // 未登记机型保留真实硬件标识，不冒充抓包手机。
        return ["iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro",
                "iPhone18,2": "iPhone 17 Pro Max", "iPhone17,3": "iPhone 16",
                "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro",
                "iPhone17,2": "iPhone 16 Pro Max"][identifier] ?? identifier
    }()

    static let userAgent: String = {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        return "bili-universal/\(build) CFNetwork/1.0 Darwin/\(systemValue("kern.osrelease")) os/ios model/\(deviceName) mobi_app/iphone build/\(build) osVer/\(osVersion) channel/pink_overseas"
    }()

    private static func systemValue(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }
}

