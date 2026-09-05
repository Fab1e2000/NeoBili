import Foundation

struct DynamicVote: Decodable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let participantCount: Int

    enum CodingKeys: String, CodingKey { case vote_id, desc, title, join_num }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexibleInt(forKey: .vote_id), id > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .vote_id, in: c, debugDescription: "缺少投票 ID")
        }
        self.id = id
        title = [c.flexibleString(forKey: .title), c.flexibleString(forKey: .desc)].compactMap { $0 }.first { !$0.isEmpty } ?? "投票"
        participantCount = c.flexibleInt(forKey: .join_num) ?? 0
    }
}

struct DynamicVoteResponse: Decodable, Sendable {
    let voteInfo: DynamicVoteInfo
    let myVotes: [Int]
    enum CodingKeys: String, CodingKey { case voteInfo = "vote_info", myVotes = "my_votes" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voteInfo = try c.decode(DynamicVoteInfo.self, forKey: .voteInfo)
        myVotes = (try? c.decode([Int].self, forKey: .myVotes)) ?? []
    }
}

struct DynamicVoteInfo: Decodable, Sendable {
    let title: String
    let endTime: Int
    let choiceCount: Int
    let participantCount: Int
    let options: [Option]
    var hasEnded: Bool { endTime > 0 && endTime <= Int(Date().timeIntervalSince1970) }
    enum CodingKeys: String, CodingKey { case title, desc, end_time, choice_cnt, join_num, options }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.flexibleString(forKey: .title) ?? c.flexibleString(forKey: .desc) ?? "投票"
        endTime = c.flexibleInt(forKey: .end_time) ?? 0
        choiceCount = max(c.flexibleInt(forKey: .choice_cnt) ?? 1, 1)
        participantCount = c.flexibleInt(forKey: .join_num) ?? 0
        options = try c.decode([Option].self, forKey: .options)
    }

    struct Option: Decodable, Identifiable, Sendable {
        let id: Int
        let text: String
        let count: Int
        let imageURL: String
        enum CodingKeys: String, CodingKey { case opt_idx, opt_desc, cnt, img_url }
        init(from decoder: Decoder) throws {
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
