import XCTest
@testable import BudsDomain

final class NordWearTests: XCTestCase {
    func testQueryAndLiveWearReports() {
        XCTAssertEqual(NordWear.query(sequence: 1).command, 0x0109)
        let reply = WasiiBudsFrame(command: 0x8109, sequence: 1,
                                   payload: [0, 2, 1, 3, 2, 1])
        XCTAssertEqual(NordWear.report(from: reply),
                       .init(left: .inEar, right: .outOfEar))
        let push = WasiiBudsFrame(command: 0x0204, sequence: 0xFF,
                                  payload: [2, 2, 1, 4, 2, 7])
        XCTAssertEqual(NordWear.report(from: push),
                       .init(left: .inCase, right: .inEar))
    }

    func testInvalidAndPartialReports() {
        XCTAssertNil(NordWear.report(from: .init(command: 0x8109, sequence: 1,
                                                 payload: [2, 1, 3])))
        XCTAssertNil(NordWear.report(from: .init(command: 0x0204, sequence: 1,
                                                 payload: [2, 1, 4, 3])))
        XCTAssertEqual(NordWear.report(from: .init(command: 0x8109, sequence: 1,
                                                   payload: [1, 2, 5])),
                       .init(left: nil, right: .outOfEar))
    }
}
