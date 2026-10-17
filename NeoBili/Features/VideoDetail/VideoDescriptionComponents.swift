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
        result.append(VideoDescriptionComponent("owner", revision: [AnyHashable(detail.owner), AnyHashable(viewModel?.ownerCard), viewModel?.relation?.isFollowing ?? false]) {
            VideoOwnerRow(owner: detail.owner, avatarURL: detail.secureAvatarURL,
                          card: viewModel?.ownerCard,
                          isFollowing: viewModel?.relation?.isFollowing ?? false,
                          onToggleFollow: onToggleFollow,
                          onOpenSpace: onOpenSpace)
                .padding(.horizontal, contentInset)
                .padding(.top, 14)

        })
        result.append(VideoDescriptionComponent(introduction:
            VideoIntroductionCard(title: detail.title, stat: detail.stat, pubdate: detail.pubdate, desc: detail.desc,
                                  isExpanded: descriptionExpanded)))
        if let tags = viewModel?.tags, !tags.isEmpty {
            result.append(VideoDescriptionComponent("tags", revision: [AnyHashable(tags)]) {
                VideoTagsRow(tags: tags, horizontalInset: contentInset) { tag in
                    onOpenTag(tag)
                }
            })
        }
        result.append(VideoDescriptionComponent("actions", revision: [AnyHashable(viewModel?.relation),
                               viewModel?.likeCount ?? 0, viewModel?.coinCount ?? 0, viewModel?.favoriteCount ?? 0,
                               viewModel?.displayedIsLiked ?? false, detail.stat.share]) {
            actionBar(detail).padding(.horizontal, contentInset)
        })
        if let season = detail.ugcSeason, !season.episodes.isEmpty {
            result.append(VideoDescriptionComponent("season", revision: [AnyHashable(season), AnyHashable(currentEpisodeIndex(season))]) {
                UgcSeasonRow(season: season, currentIndex: currentEpisodeIndex(season), onTap: onShowSeason)
                    .padding(.horizontal, contentInset)
            })
        }
        if detail.pages.count > 1 {
            result.append(VideoDescriptionComponent("parts", revision: [AnyHashable(detail.pages), AnyHashable(currentPartIndex(detail))]) {
                VideoPartsRow(parts: detail.pages, currentIndex: currentPartIndex(detail), onTap: onShowParts)
                    .padding(.horizontal, contentInset)
            })
        }
        return result.enumerated().map { index, component in
            if component.introduction != nil { return component }
            return VideoDescriptionComponent(component.id, revision: component.revision) {
                component.content.padding(.bottom, index == result.count - 1 ? 6 : 14)
            }
        }
    }

}
