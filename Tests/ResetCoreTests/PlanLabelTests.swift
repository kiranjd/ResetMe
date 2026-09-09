import XCTest
@testable import ResetCore
final class PlanLabelTests: XCTestCase {
    func testExplicitTiersAndUnknownMultiplier() {
        XCTAssertEqual(PlanLabel.format("pro"), "Pro")
        XCTAssertEqual(PlanLabel.format("pro_10x"), "Pro 10×")
        XCTAssertEqual(PlanLabel.format("pro_20x"), "Pro 20×")
        XCTAssertEqual(PlanLabel.format("pro_5x"), "Pro 5×")
        XCTAssertEqual(PlanLabel.format("prolite"), "Pro Lite")
        XCTAssertEqual(PlanLabel.format("plus"), "Plus")
    }
}
