import Foundation
import XCTest
@testable import BudsWidgetData

final class WidgetSnapshotTests: XCTestCase {
    func testReconnectClearsOldReadingsUntilNewReportsArrive() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        var snapshot = WidgetSnapshot(left: 80, right: 90, caseLevel: 50,
                                      mode: "Deep", batteryUpdatedAt: oldDate,
                                      connected: true)
        snapshot.update(left: nil, right: nil, caseLevel: nil, mode: nil,
                        connected: false, at: newDate)
        XCTAssertEqual(snapshot.left, 80)
        XCTAssertFalse(snapshot.connected)
        XCTAssertEqual(snapshot.batteryUpdatedAt, oldDate)

        snapshot.update(left: nil, right: nil, caseLevel: nil, mode: nil,
                        connected: true, at: newDate)
        XCTAssertNil(snapshot.left)
        XCTAssertNil(snapshot.right)
        XCTAssertNil(snapshot.caseLevel)
        XCTAssertNil(snapshot.mode)
        XCTAssertNil(snapshot.batteryUpdatedAt)
    }

    func testPartialReportsMergeWithinOneConnection() {
        let firstDate = Date(timeIntervalSince1970: 200)
        let secondDate = Date(timeIntervalSince1970: 300)
        var snapshot = WidgetSnapshot()
        snapshot.update(left: 80, right: nil, caseLevel: nil, mode: "Off",
                        connected: true, at: firstDate)
        snapshot.update(left: nil, right: 90, caseLevel: nil, mode: nil,
                        connected: true, at: secondDate)
        XCTAssertEqual(snapshot.left, 80)
        XCTAssertEqual(snapshot.right, 90)
        XCTAssertEqual(snapshot.mode, "Off")
        XCTAssertEqual(snapshot.batteryUpdatedAt, secondDate)
    }
}
