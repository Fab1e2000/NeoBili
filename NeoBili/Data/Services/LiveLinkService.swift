#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension LinkService {
    public static func live(session: URLSession) -> Self { Self(resolve: { url in
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        return try await session.data(for: request).1.url
    }) }
}
