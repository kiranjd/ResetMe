import XCTest
@testable import ResetCore

final class ScreenTimeHistoryTests: XCTestCase {
    func testForegroundIntervalsCrossMidnightAndUnfinishedGain() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let midnight = calendar.startOfDay(for: day)
        let events: [ScreenTimeHistory.Event] = [
            .init(at: midnight.addingTimeInterval(-60), bundle: "com.openai.codex", foreground: true),
            .init(at: midnight, bundle: "com.openai.codex", foreground: true), // duplicate gain
            .init(at: midnight.addingTimeInterval(120), bundle: "other", foreground: true),
            .init(at: midnight.addingTimeInterval(150), bundle: "com.openai.codex", foreground: false),
            .init(at: midnight.addingTimeInterval(200), bundle: "com.openai.codex", foreground: true)
        ]
        let totals = ScreenTimeHistory.totals(events + events, now: midnight.addingTimeInterval(1000), calendar: calendar)
        XCTAssertEqual(totals[midnight], 120)
        XCTAssertEqual(totals[midnight.addingTimeInterval(-86400)], 60)
    }

    func testSEGBVersionsAndMalformedData() throws {
        func le(_ value: UInt64, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
        let bundle = Array("com.openai.codex".utf8)
        let payload: [UInt8] = [24, 1, 33] + le(Double(800_000_000).bitPattern, 8) + [50, UInt8(bundle.count)] + bundle
        var v1 = [UInt8](repeating: 0, count: 56)
        v1.replaceSubrange(52..<56, with: Array("SEGB".utf8))
        v1 += le(UInt64(payload.count), 4) + [UInt8](repeating: 0, count: 28) + payload
        v1.replaceSubrange(0..<4, with: le(UInt64(v1.count), 4))
        var v2 = Array("SEGB".utf8) + le(1, 4) + [UInt8](repeating: 0, count: 24)
        v2 += [UInt8](repeating: 0, count: 8) + payload
        let end = v2.count - 32
        while v2.count % 4 != 0 { v2.append(0) }
        v2 += le(UInt64(end), 4) + le(0, 4) + le(0, 8)
        for bytes in [v1, v2] {
            let records = ScreenTimeHistory.records(bytes)
            XCTAssertEqual(records, [payload])
            let event = try XCTUnwrap(ScreenTimeHistory.decode(records[0]))
            XCTAssertEqual(event.bundle, "com.openai.codex")
            XCTAssertTrue(event.foreground)
            XCTAssertEqual(event.at.timeIntervalSinceReferenceDate, 800_000_000)
            XCTAssertTrue(ScreenTimeHistory.records(Array(bytes.prefix(20))).isEmpty)
        }
        XCTAssertNil(ScreenTimeHistory.decode([33, 0]))
        XCTAssertNil(ScreenTimeHistory.decode([50, 255, 255]))
    }

    func testMissingSourceRemainsUnknown() {
        let result = ScreenTimeHistory.readResult(root: URL(fileURLWithPath: "/nonexistent-resetme-fixture"))
        XCTAssertTrue(result.seconds.isEmpty)
        XCTAssertFalse(result.accessDenied)
    }
}
