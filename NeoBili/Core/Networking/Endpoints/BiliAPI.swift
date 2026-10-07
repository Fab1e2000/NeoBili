import Foundation

/// Endpoint-level calls, kept separate from the transport (`APIClient`) so
/// feature view models only ever talk to this facade.
///
/// 各业务领域的接口分别放在 `BiliAPI+<领域>.swift` 的扩展里（推荐、视频、播放、
/// 评论、搜索、动态、空间、账号、收藏、历史、稍后再看）。
enum BiliAPI {}
