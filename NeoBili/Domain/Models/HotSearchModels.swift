import Foundation

public struct HotSearchItem: Decodable, Identifiable {
    public let keyword: String
    public let showName: String?
    public var id: String { keyword }
    public var title: String { showName.flatMap { $0.isEmpty ? nil : $0 } ?? keyword }
    enum CodingKeys: String, CodingKey { case keyword; case showName = "show_name" }
}
