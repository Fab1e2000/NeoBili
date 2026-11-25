import Foundation

extension Error {
    /// 统一识别 Swift 任务取消与 URLSession 取消，调用方据此跳过错误提示。
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ECANCELED)
    }
}
