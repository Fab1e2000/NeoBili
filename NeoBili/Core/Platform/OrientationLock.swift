import UIKit

/// The single source of truth read by
/// `AppDelegate.application(_:supportedInterfaceOrientationsFor:)`.
///
/// This is the orientation the app is currently locked to, rather than a broad
/// set of orientations it is allowed to use. Keeping portrait in the supported
/// mask while displaying the fullscreen player lets system overlays (including
/// the screenshot thumbnail) temporarily re-evaluate the scene as portrait and
/// animate in the wrong coordinate space.
@MainActor
final class OrientationLock {
    static let shared = OrientationLock()
    var supportedOrientations: UIInterfaceOrientationMask = .portrait
    private init() {}
}
