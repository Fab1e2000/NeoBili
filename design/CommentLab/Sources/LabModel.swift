import SwiftUI
import UIKit

enum LabVariant: String, CaseIterable, Identifiable {
    case a = "A", b = "B", c = "C"
    var id: String { rawValue }
    var title: String {
        switch self { case .a: "轻量"; case .b: "紧凑"; case .c: "醒目" }
    }
    var detail: String {
        switch self {
        case .a: "描边标识 · 菜单排序 · 长按菜单"
        case .b: "浅色标识 · 文字切换 · 底部操作列表"
        case .c: "实色标识 · 分段切换 · 置顶浅色背景"
        }
    }
}

enum LabSort: String, CaseIterable, Identifiable {
    case hot = "热门", latest = "最新"
    var id: String { rawValue }
}

enum LabScene: String, CaseIterable, Identifiable {
    case video = "视频评论", dynamic = "动态评论"
    var id: String { rawValue }
}

struct LabAuthor: Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let symbol: String
    let palette: Int

    static let uploader = Self(id: 101, name: "山野放映室", symbol: "mountain.2.fill", palette: 0)
    static let viewer = Self(id: 202, name: "今天也想早点睡", symbol: "moon.stars.fill", palette: 1)
    static let me = Self(id: 303, name: "我的小小宇宙", symbol: "sparkles", palette: 2)
    static let longName = Self(id: 404, name: "一位名字很长很长仍然喜欢记录生活的观众", symbol: "leaf.fill", palette: 3)
    static let friend = Self(id: 505, name: "路过一片海", symbol: "water.waves", palette: 4)

    var color: Color {
        switch palette {
        case 0: Color(red: 0.23, green: 0.45, blue: 0.38)
        case 1: Color(red: 0.42, green: 0.37, blue: 0.64)
        case 2: Color(red: 0.73, green: 0.40, blue: 0.33)
        case 3: Color(red: 0.42, green: 0.50, blue: 0.28)
        default: Color(red: 0.25, green: 0.48, blue: 0.64)
        }
    }
}

struct LabComment: Identifiable, Hashable, Sendable {
    let id: Int
    let author: LabAuthor
    let message: String
    let minutesAgo: Int
    let location: String
    var likes: Int
    var pinned = false
    var upLiked = false
    var upReplied = false
    var hasPicture = false
    var replies: [LabComment] = []

    var isUploader: Bool { author.id == LabAuthor.uploader.id }
    var isMine: Bool { author.id == LabAuthor.me.id }
    var time: String { minutesAgo < 60 ? "\(minutesAgo)分钟前" : "\(minutesAgo / 60)小时前" }
    var displayedMessage: String {
        message.replacingOccurrences(of: "[给心心]", with: "🫶")
            .replacingOccurrences(of: "[doge]", with: "😏")
    }

    static let samples: [Self] = [
        Self(id: 1, author: .uploader,
             message: "补充一下：拍摄地在四明山，片尾的音乐和路线放在简介里啦。谢谢大家喜欢这个安静的下午 🌿",
             minutesAgo: 180, location: "浙江", likes: 362, pinned: true, upLiked: true),
        Self(id: 2, author: .viewer,
             message: "03:18 风吹过草坡的那一段，像真的坐在山里。谢谢你把这个下午留了下来。",
             minutesAgo: 120, location: "上海", likes: 128, upLiked: true, upReplied: true,
             replies: [
                Self(id: 21, author: .uploader, message: "那天录了很久的风声，能传达给你就太好了。", minutesAgo: 90, location: "浙江", likes: 42),
                Self(id: 22, author: .me, message: "戴上耳机听，真的有被治愈到 [给心心]", minutesAgo: 45, location: "陕西", likes: 8),
                Self(id: 23, author: .friend, message: "已经加入周末出行清单了！", minutesAgo: 30, location: "江苏", likes: 3)
             ]),
        Self(id: 3, author: .me,
             message: "刚好整理了上周拍的山谷。下次也想挑一个晴天，去走走这条路线。",
             minutesAgo: 5, location: "陕西", likes: 6, hasPicture: true),
        Self(id: 4, author: .longName,
             message: "很喜欢这种没有太多旁白的记录。城市里的每一天好像都被安排得满满当当，连休息也要列一张清单。\n\n看到这里忽然觉得，周末可以什么都不计划，找一条熟悉的小路慢慢走，停下来听一会儿风，也看看路边刚长出来的叶子。\n\n这段长评论保留了我想说的全部话。谢谢你的分享，希望以后还能看到这样的日常。天气好的时候，我们都记得出去走走。🌿 [doge]",
             minutesAgo: 20, location: "四川", likes: 24),
        Self(id: 5, author: .friend, message: "收藏了，等一个不用赶路的周末。", minutesAgo: 15, location: "江苏", likes: 12)
    ]
}

enum LabRoute: Hashable {
    case author(LabAuthor)
    case thread(Int)
}

struct CommentActionTarget: Identifiable {
    let comment: LabComment
    let rootID: Int?
    var id: Int { comment.id }
}

@MainActor @Observable
final class LabModel {
    var variant: LabVariant = .a
    var sort: LabSort = .hot
    var scene: LabScene = .video
    var dark = false
    var largeText = false
    var failDeletion = false
    var comments = LabComment.samples
    var path: [LabRoute] = []
    var draft = ""
    var replyTarget: CommentActionTarget?
    var pendingDeletion: CommentActionTarget?
    var actionSheet: CommentActionTarget?
    var showComparison = false
    var showImage = false
    var isPlaying = true
    var playbackTime = "03:18"
    var deletingID: Int?
    var notice: String?
    var hasRefreshed = false
    var likedIDs = Set<Int>()
    var revision = 0
    private var noticeTask: Task<Void, Never>?
    private var nextID = 1_000

    static let tint = Color(red: 0.88, green: 0.24, blue: 0.39)

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        variant = value("--variant").flatMap(LabVariant.init(rawValue:)) ?? .a
        dark = arguments.contains("--dark")
        largeText = arguments.contains("--large")
        failDeletion = arguments.contains("--delete-fails")
        if arguments.contains("--dynamic") { scene = .dynamic }
        if let thread = value("--thread").flatMap(Int.init) { path = [.thread(thread)] }
    }

    var orderedComments: [LabComment] {
        comments.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return sort == .hot ? $0.likes > $1.likes : $0.minutesAgo < $1.minutesAgo
        }
    }

    func comment(_ id: Int) -> LabComment? { comments.first { $0.id == id } }

    func announce(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
            self?.notice = nil
        }
    }

    func toggleLike(_ comment: LabComment) {
        if likedIDs.contains(comment.id) { likedIDs.remove(comment.id) }
        else { likedIDs.insert(comment.id) }
    }

    func copy(_ comment: LabComment) {
        UIPasteboard.general.string = comment.message
        announce("已复制全文")
    }

    func refresh() async {
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        hasRefreshed = true
        announce("评论已刷新")
    }

    func delete(_ target: CommentActionTarget) async {
        guard target.comment.isMine, deletingID == nil else { return }
        deletingID = target.id
        defer { deletingID = nil }
        do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
        if failDeletion { announce("删除失败，请稍后重试"); return }
        if let rootID = target.rootID, let index = comments.firstIndex(where: { $0.id == rootID }) {
            comments[index].replies.removeAll { $0.id == target.id }
        } else {
            comments.removeAll { $0.id == target.id }
            if let index = path.firstIndex(of: .thread(target.id)) { path.removeSubrange(index...) }
        }
        if replyTarget?.id == target.id || replyTarget?.rootID == target.id { replyTarget = nil }
        likedIDs.remove(target.id)
        announce("评论已删除")
    }

    func submit(in rootID: Int?) {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        nextID += 1
        let comment = LabComment(id: nextID, author: .me, message: message, minutesAgo: 0, location: "陕西", likes: 0)
        let root = replyTarget.map { $0.rootID ?? $0.id } ?? rootID
        if let root, let index = comments.firstIndex(where: { $0.id == root }) {
            comments[index].replies.insert(comment, at: 0)
        } else { comments.insert(comment, at: 0) }
        draft = ""
        replyTarget = nil
        announce("已添加到示例评论")
    }

    func reset() {
        comments = LabComment.samples
        likedIDs = []
        draft = ""
        replyTarget = nil
        path = []
        sort = .hot
        hasRefreshed = false
        revision += 1
        announce("示例已恢复")
    }
}
