#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// Builds stable description rows; navigation, player and action tasks remain with the page/model.
@MainActor
struct VideoDescriptionComponents<ActionBar: View> {
    let viewModel: VideoDetailViewModel?
    let contentInset: CGFloat
    let descriptionExpanded: Binding<Bool>
    let currentEpisodeIndex: (UgcSeason) -> Int?
    let currentPartIndex: (VideoDetail) -> Int?
    let onToggleFollow: () -> Void
    let onOpenSpace: () -> Void
    let onOpenTag: (VideoTag) -> Void
    let onShowSeason: () -> Void
    let onShowParts: () -> Void
    let actionBar: (VideoDetail) -> ActionBar

    /// Each component owns one stable cell. Expanding the introduction never
    /// resizes or rebinds the owner row above it.
    func make(_ detail: VideoDetail) -> [VideoDescriptionComponent] {
        var result: [VideoDescriptionComponent] = []
        result.append(VideoDescriptionComponent("owner", revision: [AnyHashable(detail.owner), AnyHashable(viewModel?.ownerCard), viewModel?.relation?.isFollowing ?? false],
                                                bottomSpacing: 10) {
            VideoOwnerRow(owner: detail.owner, avatarURL: detail.secureAvatarURL,
                          card: viewModel?.ownerCard,
                          isFollowing: viewModel?.relation?.isFollowing ?? false,
                          onToggleFollow: onToggleFollow,
                          onOpenSpace: onOpenSpace)
                .padding(.horizontal, contentInset)
                .padding(.top, 12)

        })
        result.append(VideoDescriptionComponent(introduction:
            VideoIntroductionCard(title: detail.title, stat: detail.stat, pubdate: detail.pubdate, desc: detail.desc,
                                  isExpanded: descriptionExpanded)))
        if let tags = viewModel?.tags, !tags.isEmpty {
            result.append(VideoDescriptionComponent("tags", revision: [AnyHashable(tags)], bottomSpacing: 16) {
                VideoTagsRow(tags: tags, horizontalInset: contentInset) { tag in
                    onOpenTag(tag)
                }
            })
        }
        result.append(VideoDescriptionComponent("actions", revision: [AnyHashable(viewModel?.relation),
                               viewModel?.likeCount ?? 0, viewModel?.coinCount ?? 0, viewModel?.favoriteCount ?? 0,
                               viewModel?.displayedIsLiked ?? false, detail.stat.share], bottomSpacing: 14) {
            actionBar(detail).padding(.horizontal, contentInset)
        })
        if let season = detail.ugcSeason {
            // The collapsed entry renders a summary, not the entire episode graph.
            // Count sections without allocating a flattened episode array.
            let total = (season.sections ?? []).reduce(0) { $0 + ($1.episodes?.count ?? 0) }
            if total > 0 {
                let title = season.title ?? ""
                let currentIndex = currentEpisodeIndex(season)
                result.append(VideoDescriptionComponent("season", revision: [title, total, AnyHashable(currentIndex)],
                                                        bottomSpacing: 14) {
                    UgcSeasonRow(title: title, total: total, currentIndex: currentIndex, onTap: onShowSeason)
                        .padding(.horizontal, contentInset)
                })
            }
        }
        if detail.pages.count > 1 {
            let currentIndex = currentPartIndex(detail)
            let currentName = currentIndex.flatMap { index in
                detail.pages.indices.contains(index - 1) ? detail.pages[index - 1].part : nil
            } ?? String(localized: "视频分集")
            let total = detail.pages.count
            result.append(VideoDescriptionComponent("parts", revision: [currentName, total, AnyHashable(currentIndex)],
                                                    bottomSpacing: 14) {
                VideoPartsRow(currentPartName: currentName, total: total, currentIndex: currentIndex, onTap: onShowParts)
                    .padding(.horizontal, contentInset)
            })
        }
        // 每一块自带下方间距；最后一块下面直接接相关视频卡片，不再有分区标题。
        return result.map { component in
            if component.introduction != nil { return component }
            return VideoDescriptionComponent(component.id, revision: component.revision) {
                component.content.padding(.bottom, component.bottomSpacing)
            }
        }
    }

}
