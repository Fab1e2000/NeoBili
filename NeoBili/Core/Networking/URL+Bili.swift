import Foundation

extension URL {
    /// Bilibili image/API responses mix `http://`, `https://` and protocol-relative
    /// (`//i0.hdslb.com/...`) URLs depending on the endpoint. Normalize all three
    /// to a valid `https://` URL.
    static func biliSecure(_ raw: String) -> URL? {
        var string = raw
        if string.hasPrefix("//") {
            string = "https:" + string
        } else if string.hasPrefix("http://") {
            string = "https://" + string.dropFirst("http://".count)
        }
        return URL(string: string)
    }
}
