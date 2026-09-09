import XCTest
import CoreGraphics
@testable import ResetCore

final class IslandMotionTests: XCTestCase {
    func testLatchAttachesEndsFirstWithoutOvershoot() {
        XCTAssertEqual(IslandMotion.latch(elapsed: 0, fraction: 0.5), 0)
        XCTAssertGreaterThan(IslandMotion.latch(elapsed: 0.06, fraction: 0), IslandMotion.latch(elapsed: 0.06, fraction: 0.5))
        for t in stride(from: 0.0, through: 1.0, by: 0.01) {
            XCTAssertTrue((0...1).contains(IslandMotion.latch(elapsed: t, fraction: 0.5)))
        }
        XCTAssertEqual(IslandMotion.latch(elapsed: 0.5, fraction: 0.5), 1, accuracy: 0.0001)
    }
    let notch = CGRect(x: 764, y: 1078, width: 199, height: 39)
    func testFixedCanvasContainsEverySurfaceWithoutMoving() {
        let canvas = IslandMotion.canvasFrame(notch)
        for p in stride(from: 0.0, through: 1.0, by: 0.01) {
            let surface = IslandMotion.frame(notch: notch, expandedHeight: 580, progress: p)
            XCTAssertTrue(canvas.contains(surface))
            XCTAssertEqual(surface.maxY, canvas.maxY, accuracy: 0.001)
        }
        let compact = IslandMotion.frame(notch: notch, expandedHeight: 314, progress: 0)
        XCTAssertFalse(compact.contains(CGPoint(x: canvas.midX, y: canvas.midY)))
    }
    func testCompactShapeExtendsOnlyLeftOfCamera() {
        let compact = IslandMotion.frame(notch: notch, expandedHeight: 314, progress: 0)
        XCTAssertEqual(compact.minX, notch.minX - 32)
        XCTAssertEqual(compact.maxX, notch.maxX)
        XCTAssertEqual(compact.height, notch.height)
    }
    func testExpandedSurfaceCentersWhileCompactStaysLeftOnly() {
        for p in stride(from: 0.0, through: 1.0, by: 0.01) {
            let frame = IslandMotion.frame(notch: notch, expandedHeight: 314, progress: p)
            XCTAssertGreaterThanOrEqual(frame.maxX, notch.maxX)
            XCTAssertLessThanOrEqual(frame.maxX, notch.midX + 174)
            XCTAssertEqual(frame.maxY, notch.maxY, accuracy: 0.001)
        }
    }
    func testBreadthLeadsDepthAndContentAppearsWithinSurface() {
        XCTAssertEqual(IslandMotion.straighten(0.25), 1)
        XCTAssertEqual(IslandMotion.travel(0.25), 0)
        XCTAssertEqual(IslandMotion.travel(0.75), 1)
        XCTAssertEqual(IslandMotion.content(0.75), 0)
        XCTAssertEqual(IslandMotion.content(1), 1)
        XCTAssertEqual(IslandMotion.content(0), 0)
        XCTAssertEqual(IslandMotion.compactOpacity(1), 0)
        XCTAssertEqual(IslandMotion.row(1, index: 4), 1)
        XCTAssertEqual(IslandMotion.row(0.5, index: 0), IslandMotion.row(0.5, index: 3))
        let expanded = IslandMotion.frame(notch: notch, expandedHeight: 314, progress: 1)
        XCTAssertEqual(expanded.midX, notch.midX)
        XCTAssertEqual(expanded.width, 348)
        XCTAssertEqual(expanded.height, 314)
    }
    func testSpringReversalStartsFromCurrentPositionAndVelocity() {
        let open = IslandMotion.spring(value: 0, velocity: 0, target: 1, elapsed: 0.1, frequency: 17)
        let reversal = IslandMotion.spring(value: open.value, velocity: open.velocity, target: 0, elapsed: 0, frequency: 21)
        XCTAssertEqual(reversal.value, open.value, accuracy: 0.000001)
        XCTAssertEqual(reversal.velocity, open.velocity, accuracy: 0.000001)
        let settled = IslandMotion.spring(value: open.value, velocity: open.velocity, target: 0, elapsed: 1, frequency: 21)
        XCTAssertEqual(settled.value, 0, accuracy: 0.000001)
    }
    func testCollapseDoesNotHoldWidthWhileHeightDisappears() {
        for p in stride(from: 0.05, through: 0.95, by: 0.05) {
            XCTAssertLessThan(abs(IslandMotion.breadth(p) - IslandMotion.depth(p)), 0.06)
            if IslandMotion.content(p) > 0 { XCTAssertEqual(IslandMotion.travel(p), 1) }
        }
    }
}
