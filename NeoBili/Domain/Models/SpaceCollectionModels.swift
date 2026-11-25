import Foundation

public enum SpaceCollectionKind: String, Hashable, Sendable {
    case season, series
}

public struct SpaceCollectionSummary: Identifiable, Hashable, Sendable {
    public let kind: SpaceCollectionKind
    public let collectionID: Int
    public let mid: Int
    public let name: String
    public let description: String
    public let cover: String
    public let total: Int
    public let updatedAt: Int

    public var id: String { "\(kind.rawValue):\(collectionID)" }

    init(kind: SpaceCollectionKind, collectionID: Int, mid: Int, name: String, description: String,
         cover: String, total: Int, updatedAt: Int) {
        self.kind = kind
        self.collectionID = collectionID
        self.mid = mid
        self.name = name
        self.description = description
        self.cover = cover
        self.total = total
        self.updatedAt = updatedAt
    }
}

public struct SpaceCollectionListPage: Decodable, Sendable {
    public let collections: [SpaceCollectionSummary]
    public let rawItemCount: Int
    public let pageNumber: Int?
    public let pageSize: Int?
    public let total: Int?

    private enum CodingKeys: String, CodingKey {
        case itemsLists = "items_lists"
        case seasons = "seasons_list"
        case series = "series_list"
        case page
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let items = try root.nestedContainer(keyedBy: CodingKeys.self, forKey: .itemsLists)
        let pagination = try items.decodeIfPresent(CollectionPagination.self, forKey: .page)
        let outerPage = try root.decodeIfPresent(CollectionPagination.self, forKey: .page)
        pageNumber = pagination?.number ?? outerPage?.number
        pageSize = pagination?.size ?? outerPage?.size
        total = pagination?.total ?? outerPage?.total
        let seasons = try items.decodeIfPresent(LenientList<CollectionEntry>.self, forKey: .seasons)
        let series = try items.decodeIfPresent(LenientList<CollectionEntry>.self, forKey: .series)
        rawItemCount = (seasons?.rawCount ?? 0) + (series?.rawCount ?? 0)
        collections = (seasons?.elements ?? []).compactMap { $0.summary(kind: .season) }
            + (series?.elements ?? []).compactMap { $0.summary(kind: .series) }
    }

    public func hasMore(after loadedCount: Int, requestedPage: Int? = nil) -> Bool {
        CollectionPagination.hasMore(number: pageNumber ?? requestedPage, size: pageSize, total: total, loadedCount: loadedCount)
    }
}

public struct SpaceCollectionArchive: Decodable, Identifiable, Hashable, Sendable, VideoDimensionProviding {
    public let aid: Int
    public let bvid: String
    public let title: String
    public let pic: String
    public let duration: Int
    public let pubdate: Int
    public let viewCount: Int
    public let dimension: VideoDimension?

    public var id: String { bvid }
    public var dimensionLookupBVID: String? { bvid }
    public var videoDurationSeconds: Int? { duration > 0 ? duration : nil }

    public var durationText: String {
        guard duration > 0 else { return "" }
        let hours = duration / 3600
        let minutes = duration / 60 % 60
        let seconds = duration % 60
        let minuteSecond = String(format: "%02d:%02d", minutes, seconds)
        return hours > 0 ? "\(hours):\(minuteSecond)" : minuteSecond
    }

    private enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, duration, pubdate, stat, view, dimension
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try fields.decode(String.self, forKey: .bvid)
        guard !bvid.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .bvid, in: fields, debugDescription: "Missing video identifier")
        }
        aid = fields.flexibleInt(forKey: .aid) ?? 0
        title = fields.flexibleString(forKey: .title) ?? ""
        pic = fields.flexibleString(forKey: .pic) ?? ""
        duration = max(0, fields.flexibleInt(forKey: .duration)
            ?? fields.flexibleString(forKey: .duration).flatMap(VideoDuration.seconds(from:)) ?? 0)
        pubdate = fields.flexibleInt(forKey: .pubdate) ?? 0
        let stat = try? fields.nestedContainer(keyedBy: CodingKeys.self, forKey: .stat)
        viewCount = stat?.flexibleInt(forKey: .view) ?? -1
        dimension = try? fields.decode(VideoDimension.self, forKey: .dimension)
    }
}

public struct SpaceCollectionArchivePage: Decodable, Sendable {
    public let archives: [SpaceCollectionArchive]
    public let rawItemCount: Int
    public let pageNumber: Int?
    public let pageSize: Int?
    public let total: Int?

    private enum CodingKeys: String, CodingKey { case archives, page }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let items = try fields.decodeIfPresent(LenientList<SpaceCollectionArchive>.self, forKey: .archives)
        archives = items?.elements ?? []
        rawItemCount = items?.rawCount ?? 0
        let pagination = try fields.decodeIfPresent(CollectionPagination.self, forKey: .page)
        pageNumber = pagination?.number
        pageSize = pagination?.size
        total = pagination?.total
    }

    public func hasMore(after loadedCount: Int, requestedPage: Int? = nil) -> Bool {
        CollectionPagination.hasMore(number: pageNumber ?? requestedPage, size: pageSize, total: total, loadedCount: loadedCount)
    }
}

private struct CollectionPagination: Decodable {
    let number: Int?
    let size: Int?
    let total: Int?

    private enum CodingKeys: String, CodingKey {
        case pageNumber = "page_num"
        case pageSize = "page_size"
        case num, size, total
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        number = fields.flexibleInt(forKey: .pageNumber) ?? fields.flexibleInt(forKey: .num)
        size = fields.flexibleInt(forKey: .pageSize) ?? fields.flexibleInt(forKey: .size)
        total = fields.flexibleInt(forKey: .total)
    }

    static func hasMore(number: Int?, size: Int?, total: Int?, loadedCount: Int) -> Bool {
        guard let total, total > 0 else { return false }
        if let number, number > 0, let size, size > 0 {
            return number <= (total - 1) / size
        }
        return loadedCount < total
    }
}

private struct CollectionEntry: Decodable {
    let seasonID: Int?
    let seriesID: Int?
    let mid: Int
    let name: String
    let description: String
    let cover: String
    let total: Int
    let updatedAt: Int

    private enum CodingKeys: String, CodingKey {
        case meta, archives, mid, name, description, cover, total, pic, mtime, ptime
        case seasonID = "season_id"
        case seriesID = "series_id"
        case lastUpdate = "last_update_ts"
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let meta = try fields.nestedContainer(keyedBy: CodingKeys.self, forKey: .meta)
        seasonID = meta.flexibleInt(forKey: .seasonID)
        seriesID = meta.flexibleInt(forKey: .seriesID)
        mid = meta.flexibleInt(forKey: .mid) ?? 0
        name = meta.flexibleString(forKey: .name) ?? ""
        description = meta.flexibleString(forKey: .description) ?? ""
        let metaCover = meta.flexibleString(forKey: .cover) ?? ""
        if metaCover.isEmpty, var previews = try? fields.nestedUnkeyedContainer(forKey: .archives),
           let first = try? previews.nestedContainer(keyedBy: CodingKeys.self) {
            cover = first.flexibleString(forKey: .pic) ?? ""
        } else {
            cover = metaCover
        }
        total = max(0, meta.flexibleInt(forKey: .total) ?? 0)
        updatedAt = meta.flexibleInt(forKey: .lastUpdate) ?? meta.flexibleInt(forKey: .mtime)
            ?? meta.flexibleInt(forKey: .ptime) ?? 0
    }

    func summary(kind: SpaceCollectionKind) -> SpaceCollectionSummary? {
        guard let id = kind == .season ? seasonID : seriesID, id > 0 else { return nil }
        return SpaceCollectionSummary(kind: kind, collectionID: id, mid: mid, name: name,
                                      description: description, cover: cover, total: total, updatedAt: updatedAt)
    }
}
