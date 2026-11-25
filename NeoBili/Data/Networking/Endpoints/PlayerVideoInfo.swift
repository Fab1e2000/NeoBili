import Foundation
import NeoBiliDomain

struct PlayerVideoInfo: Decodable {
    struct Subtitle: Decodable {
        struct Track: Decodable {
            let lan: String
            let lanDoc: String
            let subtitleURL: String

            enum CodingKeys: String, CodingKey { case lan; case lanDoc = "lan_doc"; case subtitleURL = "subtitle_url" }
        }

        let subtitles: [Track]
    }

    private struct ViewPoint: Decodable {
        let chapter: VideoChapter?

        enum CodingKeys: String, CodingKey { case type, from, to, content, imgUrl }

        init(from decoder: Decoder) throws {
            guard let fields = try? decoder.container(keyedBy: CodingKeys.self),
                  (try? fields.decode(Int.self, forKey: .type)) == 2,
                  let from = try? fields.decode(Double.self, forKey: .from),
                  let to = try? fields.decode(Double.self, forKey: .to),
                  from.isFinite, to.isFinite, from >= 0, to > from,
                  let content = try? fields.decode(String.self, forKey: .content) else {
                chapter = nil
                return
            }
            let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageURL = (try? fields.decode(String.self, forKey: .imgUrl)).flatMap { URL.biliSecure($0) }
            chapter = title.isEmpty ? nil : VideoChapter(from: from, to: to, title: title, imageURL: imageURL)
        }
    }

    let subtitle: Subtitle?
    let chapters: [VideoChapter]

    private enum CodingKeys: String, CodingKey { case subtitle; case viewPoints = "view_points" }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        subtitle = try? fields.decode(Subtitle.self, forKey: .subtitle)
        let points = (try? fields.decode([ViewPoint].self, forKey: .viewPoints)) ?? []
        var seen = Set<VideoChapter>()
        chapters = points.compactMap(\.chapter).filter { seen.insert($0).inserted }.sorted { $0.from < $1.from }
    }
}
