import Foundation

extension Error {
    /// Keep recovery guidance readable while preserving actionable service errors.
    var loadFailureDescription: String {
        switch (self as? URLError)?.code {
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            String(localized: "暂时无法与哔哩哔哩建立安全连接，请稍后重试。")
        case .notConnectedToInternet:
            String(localized: "当前没有网络连接。")
        case .timedOut:
            String(localized: "请求超时，请稍后重试。")
        default:
            localizedDescription
        }
    }
}
