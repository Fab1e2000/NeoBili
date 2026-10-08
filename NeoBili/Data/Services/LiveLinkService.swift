import Foundation

extension LinkService {
    static let live = Self(resolve: { url in
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        return try await AppNetwork.session.data(for: request).1.url
    })
}
