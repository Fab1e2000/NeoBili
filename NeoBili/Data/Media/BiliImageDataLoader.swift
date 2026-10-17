import Foundation

struct BiliImageDataLoader: Sendable {
    private let session: URLSession
    init(session: URLSession) { self.session = session }
    private let requests = ImageRequestPool<URL, Data>()

    func data(for url: URL) async throws -> Data {
        try await requests.value(for: url) { [session] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            let (data, response) = try await session.data(for: request)
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                throw BiliAPIError.httpStatus(response.statusCode)
            }
            return data
        }
    }
}
