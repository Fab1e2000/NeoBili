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
    private(set) var supportedOrientations: UIInterfaceOrientationMask = .portrait
    private(set) var playbackOwner: UUID?

    // Internal construction keeps ownership tests independent of the application's singleton.
    init() {}

    @discardableResult
    func request(_ orientation: UIInterfaceOrientationMask, owner: UUID? = nil) -> Bool {
        // Background pages may appear again during a native presentation/rotation.
        // Their default portrait request cannot override the fullscreen player.
        guard owner != nil || playbackOwner == nil else { return false }
        if let owner { playbackOwner = owner }
        guard supportedOrientations != orientation else { return false }
        supportedOrientations = orientation
        return true
    }

    @discardableResult
    func endPlayback(owner: UUID) -> Bool {
        guard playbackOwner == owner else { return false }
        playbackOwner = nil
        return request(.portrait)
    }
}
