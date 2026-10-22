#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

final class RecommendationUnblockTests: XCTestCase {
    func testUnblockSurvivesReloadAndPreservesOtherFiltersAndOwners() throws {
        let suite = "neobili.unblock.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(30, forKey: RecommendationFilter.minDurationKey)
        RecommendationFilter.block(11, defaults: defaults)
        RecommendationFilter.block(22, defaults: defaults)
        RecommendationFilter.block(11, defaults: defaults)
        XCTAssertTrue(RecommendationFilter.current(defaults).dropsOwner(11))
        RecommendationFilter.unblock(11, defaults: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        let filter = RecommendationFilter.current(reopened)
        XCTAssertFalse(filter.dropsOwner(11))
        XCTAssertTrue(filter.dropsOwner(22))
        XCTAssertEqual(filter.minDuration, 30)
        RecommendationFilter.unblock(22, defaults: reopened)
        RecommendationFilter.unblock(99, defaults: reopened)
        XCTAssertTrue(RecommendationFilter.current(reopened).blockedMids.isEmpty)
        XCTAssertNil(reopened.object(forKey: RecommendationFilter.blockedMidsKey))
    }
}
