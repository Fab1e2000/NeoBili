import Foundation

enum VideoFullscreenOrientation {
    case portrait
    case landscape

    static func preferred(for aspectRatio: Double?) -> Self {
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0, aspectRatio < 1 else {
            return .landscape
        }
        return .portrait
    }
}
