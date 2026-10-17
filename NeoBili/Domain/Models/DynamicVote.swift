import Foundation

public struct DynamicVote: Decodable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let participantCount: Int

    enum CodingKeys: String, CodingKey { case vote_id, desc, title, join_num }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexibleInt(forKey: .vote_id), id > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .vote_id, in: c, debugDescription: "缺少投票 ID")
        }
        self.id = id
        title = [c.flexibleString(forKey: .title), c.flexibleString(forKey: .desc)].compactMap { $0 }.first { !$0.isEmpty } ?? "投票"
        participantCount = c.flexibleInt(forKey: .join_num) ?? 0
    }
}

public struct DynamicVoteResponse: Decodable, Sendable {
    public let voteInfo: DynamicVoteInfo
    public let myVotes: [Int]
    enum CodingKeys: String, CodingKey { case voteInfo = "vote_info", myVotes = "my_votes" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voteInfo = try c.decode(DynamicVoteInfo.self, forKey: .voteInfo)
        myVotes = (try? c.decode([Int].self, forKey: .myVotes)) ?? []
    }
}

public struct DynamicVoteInfo: Decodable, Sendable {
    public let title: String
    public let endTime: Int
    public let choiceCount: Int
    public let participantCount: Int
    public let options: [Option]
    public var hasEnded: Bool { endTime > 0 && endTime <= Int(Date().timeIntervalSince1970) }
    enum CodingKeys: String, CodingKey { case title, desc, end_time, choice_cnt, join_num, options }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.flexibleString(forKey: .title) ?? c.flexibleString(forKey: .desc) ?? "投票"
        endTime = c.flexibleInt(forKey: .end_time) ?? 0
        choiceCount = max(c.flexibleInt(forKey: .choice_cnt) ?? 1, 1)
        participantCount = c.flexibleInt(forKey: .join_num) ?? 0
        options = try c.decode([Option].self, forKey: .options)
    }

    public struct Option: Decodable, Identifiable, Sendable {
        public let id: Int
        public let text: String
        public let count: Int
        public let imageURL: String
        enum CodingKeys: String, CodingKey { case opt_idx, opt_desc, cnt, img_url }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let id = c.flexibleInt(forKey: .opt_idx) else {
                throw DecodingError.dataCorruptedError(forKey: .opt_idx, in: c, debugDescription: "缺少选项 ID")
            }
            self.id = id
            text = c.flexibleString(forKey: .opt_desc) ?? ""
            count = c.flexibleInt(forKey: .cnt) ?? 0
            imageURL = c.flexibleString(forKey: .img_url) ?? ""
        }
    }
}
