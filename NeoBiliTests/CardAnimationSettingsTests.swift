import XCTest
@testable import NeoBili

final class CardAnimationSettingsTests: XCTestCase {
    @MainActor func testSkippedEntranceCannotReplayWhenRecycled() {
        let clock = VideoEntranceClock()
        clock.prepare(ids: ["first", "second"], generation: 0, reset: true)
        clock.admit(["first"], animated: false)
        clock.admit(["first", "second"])
        XCTAssertEqual(clock.starts["first"], 0)
        XCTAssertGreaterThan(clock.starts["second"] ?? 0, 0)
        clock.finishAnimations()
        clock.admit(["first", "second"])
        XCTAssertTrue(clock.starts.values.allSatisfy { $0 == 0 })
    }

    func testEveryCustomAnimationDefaultsToEnabled() throws {
        let suite = "neobili.card-animations.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for category in CardAnimationCategory.allCases {
            for phase in [CardAnimationPhase.enter, .exit] {
                XCTAssertTrue(CardAnimationSettings.isEnabled(category: category, phase: phase, defaults: defaults))
            }
        }
    }

    func testMasterSwitchPreservesIndependentCategoryChoices() throws {
        let suite = "neobili.card-animations.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: CardAnimationSettings.videoEnterKey)
        defaults.set(false, forKey: CardAnimationSettings.dynamicExitKey)
        defaults.set(false, forKey: CardAnimationSettings.masterKey)
        for category in CardAnimationCategory.allCases {
            XCTAssertFalse(CardAnimationSettings.isEnabled(category: category, phase: .enter, defaults: defaults))
            XCTAssertFalse(CardAnimationSettings.isEnabled(category: category, phase: .exit, defaults: defaults))
        }
        defaults.set(true, forKey: CardAnimationSettings.masterKey)
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .video, phase: .enter, defaults: defaults))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .exit, defaults: defaults))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .dynamic, phase: .enter, defaults: defaults))
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .dynamic, phase: .exit, defaults: defaults))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .page, phase: .enter, defaults: defaults))
    }

    func testUnconfiguredSourcesPreserveLegacyVideoPreferences() throws {
        let suite = "neobili.card-source.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for source in VideoCardAnimationSource.allCases {
            XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: source, defaults: defaults))
            XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .exit, source: source, defaults: defaults))
        }
        defaults.set(false, forKey: CardAnimationSettings.videoEnterKey)
        for source in VideoCardAnimationSource.allCases {
            XCTAssertFalse(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: source, defaults: defaults))
            XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .exit, source: source, defaults: defaults))
        }
    }

    func testSourceOverridesAreIndependentAndSurviveMasterToggle() throws {
        let suite = "neobili.card-source.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: CardAnimationSettings.videoEnterKey)
        defaults.set(true, forKey: CardAnimationSettings.storageKey(source: .search, phase: .enter))
        defaults.set(false, forKey: CardAnimationSettings.storageKey(source: .history, phase: .exit))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: .search, defaults: defaults))
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: .recommendation, defaults: defaults))
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .video, phase: .exit, source: .history, defaults: defaults))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .exit, source: .favorites, defaults: defaults))

        defaults.set(false, forKey: CardAnimationSettings.masterKey)
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: .search, defaults: defaults))
        defaults.set(true, forKey: CardAnimationSettings.masterKey)
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .video, phase: .enter, source: .search, defaults: defaults))
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .video, phase: .exit, source: .history, defaults: defaults))
    }

    func testVideoSourceDoesNotOverrideDynamicOrPageSettings() throws {
        let suite = "neobili.card-source.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: CardAnimationSettings.storageKey(source: .space, phase: .enter))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .dynamic, phase: .enter, source: .space, defaults: defaults))
        defaults.set(false, forKey: CardAnimationSettings.dynamicEnterKey)
        XCTAssertFalse(CardAnimationSettings.isEnabled(category: .dynamic, phase: .enter, source: .space, defaults: defaults))
        XCTAssertTrue(CardAnimationSettings.isEnabled(category: .page, phase: .enter, source: .space, defaults: defaults))
    }

    func testSettingsOnlyExposeExistingCustomAnimationPhases() {
        XCTAssertEqual(VideoCardAnimationSource.recommendation.supportedPhases, [.enter, .exit])
        XCTAssertEqual(VideoCardAnimationSource.live.supportedPhases, [.enter, .exit])
        for source in [VideoCardAnimationSource.search, .space] {
            XCTAssertEqual(source.supportedPhases, [.enter])
        }
        for source in [VideoCardAnimationSource.favorites, .history, .watchLater] {
            XCTAssertEqual(source.supportedPhases, [.exit])
        }
        XCTAssertTrue(VideoCardAnimationSource.collection.supportedPhases.isEmpty)
        XCTAssertTrue(VideoCardAnimationSource.relatedVideos.supportedPhases.isEmpty)
    }
}
