import XCTest
@testable import ResetCore

final class IndicatorVisibilityTests: XCTestCase {
    func testQuietDefaultAndIndependentRevealReasons() {
        XCTAssertFalse(IndicatorVisibility.shouldShow(alwaysOn: false, hovered: false, expanded: false, recentChange: false, activeAppSelected: false))
        for index in 0..<5 {
            let flags = (0..<5).map { $0 == index }
            XCTAssertTrue(IndicatorVisibility.shouldShow(alwaysOn: flags[0], hovered: flags[1], expanded: flags[2], recentChange: flags[3], activeAppSelected: flags[4]))
        }
    }
    private func bucket(_ percent: Double, reset: Double = 100) -> LimitBucket {
        LimitBucket(limitId: "codex", limitName: nil, primary: LimitWindow(usedPercent: percent, windowDurationMins: 300, resetsAt: reset), secondary: nil, planType: nil)
    }
    func testInitialReadUnchangedRefreshAndMissingDataStayQuiet() {
        XCTAssertFalse(IndicatorVisibility.usageChanged(from: [], to: [bucket(25)]))
        XCTAssertFalse(IndicatorVisibility.usageChanged(from: [bucket(25)], to: [bucket(25)]))
        XCTAssertFalse(IndicatorVisibility.usageChanged(from: [bucket(25)], to: []))
        XCTAssertFalse(IndicatorVisibility.usageChanged(from: [bucket(25)], to: [bucket(25, reset: 200)]))
    }
    func testConsumptionAndResetReveal() {
        XCTAssertTrue(IndicatorVisibility.usageChanged(from: [bucket(25)], to: [bucket(26)]))
        XCTAssertTrue(IndicatorVisibility.usageChanged(from: [bucket(25)], to: [bucket(0, reset: 200)]))
    }
}
