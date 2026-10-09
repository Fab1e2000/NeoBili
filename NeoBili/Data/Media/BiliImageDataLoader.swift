import Foundation

enum BiliImageDataLoader {
    private static let requests = ImageRequestPool<URL, Data>()

    static func data(for url: URL) async throws -> Data {
        try await requests.value(for: url) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            let (data, response) = try await AppNetwork.session.data(for: request)
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw BiliAPIError.httpStatus(response.statusCode)
            }
            return data
        }
    }
}
