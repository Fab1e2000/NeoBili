import Foundation

struct HotSearchItem: Decodable, Identifiable {
    let keyword: String
    let showName: String?
    var id: String { keyword }
    var title: String { showName.flatMap { $0.isEmpty ? nil : $0 } ?? keyword }
    enum CodingKeys: String, CodingKey { case keyword; case showName = "show_name" }
}
