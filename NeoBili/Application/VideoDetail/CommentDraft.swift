import Observation

@MainActor
@Observable
final class CommentDraft {
    var text = ""
    var target: CommentReplyTarget?
}

struct CommentReplyTarget {
    let root: Int
    let parent: Int
    let name: String
}
