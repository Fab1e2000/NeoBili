import UIKit
import XCTest
@testable import NeoBili

/// Plain UIKit surfaces exercise ownership without starting MPV or making any
/// network request. Both presentation containers remain alive during handoff.
@MainActor
final class MiniPlayerSurfaceTests: XCTestCase {
    private final class Owner {
        enum Destination { case page, mini }
        var destination: Destination = .page
    }

    func testRelatedVideoReplacementTransfersToExistingMiniWithoutAnotherLayout() {
        let originalOwnership = PlayerSurfaceOwnership()
        let replacementOwnership = PlayerSurfaceOwnership()
        let original = UIViewController()
        let replacement = UIViewController()
        let page = PlayerSurfaceContainerController(content: original, canPresent: { false })
        let mini = PlayerSurfaceContainerController(content: original, canPresent: { false })
        page.configure(content: original, ownership: originalOwnership, presentation: .page)
        mini.configure(content: original, ownership: originalOwnership, presentation: .mini)
        page.loadViewIfNeeded()
        mini.loadViewIfNeeded()
        XCTAssertTrue(original.parent === page)

        // Use the production reconfiguration path. Both UIKit containers keep
        // their identity and dimensions when the related video has the same ratio.
        page.configure(content: replacement, ownership: replacementOwnership, presentation: .page)
        mini.configure(content: replacement, ownership: replacementOwnership, presentation: .mini)
        XCTAssertNil(original.parent)
        XCTAssertTrue(replacement.parent === page)
        originalOwnership.presentation = .mini
        XCTAssertTrue(replacement.parent === page, "A late old-session notification must not affect its replacement")

        // This is the sole state change made by the dismissal completion. Do not
        // manually call viewDidLayoutSubviews/adopt: that hid the old regression.
        replacementOwnership.presentation = .mini
        XCTAssertTrue(replacement.parent === mini)
        XCTAssertTrue(replacement.view.superview === mini.view)
        XCTAssertEqual(mini.children.count, 1)
        XCTAssertTrue(page.children.isEmpty)

        page.viewDidLayoutSubviews()
        XCTAssertTrue(replacement.parent === mini)
        replacementOwnership.presentation = .page
        XCTAssertTrue(replacement.parent === page, "Expansion also transfers synchronously")
    }

    func testMiniBoundAfterDismissalImmediatelyAdoptsReplacementSurface() {
        let originalOwnership = PlayerSurfaceOwnership()
        let replacementOwnership = PlayerSurfaceOwnership()
        let original = UIViewController()
        let replacement = UIViewController()
        let page = PlayerSurfaceContainerController(content: replacement, canPresent: { false })
        let mini = PlayerSurfaceContainerController(content: original, canPresent: { false })
        mini.configure(content: original, ownership: originalOwnership, presentation: .mini)
        page.configure(content: replacement, ownership: replacementOwnership, presentation: .page)
        mini.loadViewIfNeeded()
        page.loadViewIfNeeded()

        replacementOwnership.presentation = .mini
        // SwiftUI can deliver this rebind after the native dismissal callback.
        mini.configure(content: replacement, ownership: replacementOwnership, presentation: .mini)
        XCTAssertTrue(replacement.parent === mini)
        originalOwnership.presentation = .mini
        XCTAssertNil(original.parent)
        XCTAssertTrue(replacement.parent === mini)
        mini.stopObservingOwnership()
        replacementOwnership.presentation = .page
        XCTAssertTrue(replacement.parent === page)
    }

    func testDismantledMiniCannotReclaimSurfaceThroughLateUIKitCallbacks() {
        let ownership = PlayerSurfaceOwnership()
        ownership.presentation = .mini
        let content = UIViewController()
        let stale = PlayerSurfaceContainerController(content: content, canPresent: { false })
        stale.configure(content: content, ownership: ownership, presentation: .mini)
        stale.loadViewIfNeeded()
        stale.stopObservingOwnership()
        let current = PlayerSurfaceContainerController(content: content, canPresent: { false })
        current.configure(content: content, ownership: ownership, presentation: .mini)
        current.loadViewIfNeeded()
        XCTAssertTrue(content.parent === current)
        stale.viewWillAppear(false)
        stale.viewDidLayoutSubviews()
        stale.adopt(content)
        XCTAssertTrue(content.parent === current)
        XCTAssertTrue(stale.children.isEmpty)
    }

    func testInactiveSurfaceCannotAttachDuringLoadLayoutOrAdoption() {
        let owner = Owner()
        let content = UIViewController()
        let mini = PlayerSurfaceContainerController(content: content,
                                                     canPresent: { owner.destination == .mini })
        mini.loadViewIfNeeded()
        XCTAssertNil(content.parent)
        mini.viewWillAppear(false)
        mini.viewDidLayoutSubviews()
        mini.adopt(content)
        XCTAssertNil(content.parent, "An inactive host must not claim a renderer merely because it receives UIKit callbacks")
        XCTAssertTrue(mini.children.isEmpty)
    }

    func testOwnershipSwitchTransfersSameSurfaceAndIgnoresLateOldHostCallbacks() {
        let owner = Owner()
        let content = UIViewController()
        let page = PlayerSurfaceContainerController(content: content,
                                                     canPresent: { owner.destination == .page })
        let mini = PlayerSurfaceContainerController(content: content,
                                                     canPresent: { owner.destination == .mini })
        page.loadViewIfNeeded()
        mini.loadViewIfNeeded()
        XCTAssertTrue(content.parent === page)

        owner.destination = .mini
        mini.viewDidLayoutSubviews()
        XCTAssertTrue(content.parent === mini)
        XCTAssertTrue(page.children.isEmpty)
        XCTAssertEqual(mini.children.count, 1)

        // An old SwiftUI page can still relayout/update while cover dismissal
        // finishes. None of these events may steal the active mini's renderer.
        page.viewWillAppear(false)
        page.viewDidLayoutSubviews()
        page.adopt(content)
        XCTAssertTrue(content.parent === mini)
        XCTAssertTrue(content.view.superview === mini.view)

        owner.destination = .page
        page.viewWillAppear(false)
        XCTAssertTrue(content.parent === page)
        mini.viewWillAppear(false)
        mini.viewDidLayoutSubviews()
        mini.adopt(content)
        XCTAssertTrue(content.parent === page, "Expanding must have the same protection against stale mini callbacks")
        XCTAssertTrue(mini.children.isEmpty)
    }

    func testOldContainerAdoptingAnotherSessionDoesNotDetachTransferredSurface() {
        let owner = Owner()
        let playing = UIViewController()
        let replacement = UIViewController()
        let page = PlayerSurfaceContainerController(content: playing,
                                                     canPresent: { owner.destination == .page })
        let mini = PlayerSurfaceContainerController(content: playing,
                                                     canPresent: { owner.destination == .mini })
        page.loadViewIfNeeded()
        mini.loadViewIfNeeded()
        owner.destination = .mini
        mini.viewDidLayoutSubviews()
        XCTAssertTrue(playing.parent === mini)

        // The stale page still remembers `playing` but no longer owns it.
        // Updating its session must only detach a child owned by that page.
        page.adopt(replacement)
        XCTAssertTrue(playing.parent === mini)
        XCTAssertTrue(playing.view.superview === mini.view)
        XCTAssertNil(replacement.parent)
        XCTAssertTrue(page.children.isEmpty)

        owner.destination = .page
        page.viewDidLayoutSubviews()
        XCTAssertTrue(replacement.parent === page)
        XCTAssertTrue(playing.parent === mini, "The old owner's unrelated child remains under its own lifecycle")
    }

    func testRepeatedHandoffsKeepOneParentAndDoNotAccumulateChildren() {
        let owner = Owner()
        let content = UIViewController()
        let page = PlayerSurfaceContainerController(content: content,
                                                     canPresent: { owner.destination == .page })
        let mini = PlayerSurfaceContainerController(content: content,
                                                     canPresent: { owner.destination == .mini })
        page.loadViewIfNeeded()
        mini.loadViewIfNeeded()
        for index in 0..<20 {
            owner.destination = index.isMultiple(of: 2) ? .mini : .page
            let active = owner.destination == .mini ? mini : page
            let inactive = owner.destination == .mini ? page : mini
            active.viewDidLayoutSubviews()
            inactive.viewDidLayoutSubviews()
            inactive.adopt(content)
            XCTAssertTrue(content.parent === active)
            XCTAssertTrue(content.view.superview === active.view)
            XCTAssertEqual(active.children.count, 1)
            XCTAssertTrue(inactive.children.isEmpty)
        }
    }
}
