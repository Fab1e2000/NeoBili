import UIKit

/// Owns prefetch consumers as they transfer from index paths to visible cells.
@MainActor
final class HomeFeedImagePrefetcher {
    private var imagePrefetches: [IndexPath: [Task<Void, Never>]] = [:]
    private var displayedImagePrefetches: [ObjectIdentifier: [Task<Void, Never>]] = [:]

    func prefetch(indexPath: IndexPath, video: VideoSummary, width: CGFloat,
                  scale: CGFloat, pipeline: BiliImagePipeline) {
        guard imagePrefetches[indexPath] == nil else { return }
        let cover = video.isLargeRecommendationCard
            ? CGSize(width: width - HomeCardLayout.horizontalInset * 2,
                     height: (width - HomeCardLayout.horizontalInset * 2) / HomeCardLayout.largeCoverAspectRatio)
            : HomeCardLayout.coverSize(for: width)
        imagePrefetches[indexPath] = [
            BiliImageLoader.prefetch(video.secureCoverURL, pointSize: cover, scale: scale, pipeline: pipeline),
            BiliImageLoader.prefetch(video.secureAvatarURL, pointSize: HomeCardLayout.avatarSize, scale: scale, pipeline: pipeline)
        ].compactMap { $0 }
    }

    func cancel(indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            imagePrefetches.removeValue(forKey: indexPath)?.forEach { $0.cancel() }
        }
    }

    func willDisplay(cellID: ObjectIdentifier, indexPath: IndexPath) {
        displayedImagePrefetches.removeValue(forKey: cellID)?.forEach { $0.cancel() }
        displayedImagePrefetches[cellID] = imagePrefetches.removeValue(forKey: indexPath)
    }

    func didEndDisplaying(cellID: ObjectIdentifier) {
        displayedImagePrefetches.removeValue(forKey: cellID)?.forEach { $0.cancel() }
    }

    func cancelAll() {
        imagePrefetches.values.forEach { $0.forEach { $0.cancel() } }
        imagePrefetches.removeAll()
        displayedImagePrefetches.values.forEach { $0.forEach { $0.cancel() } }
        displayedImagePrefetches.removeAll()
    }
}
