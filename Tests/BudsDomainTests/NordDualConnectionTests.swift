import XCTest
@testable import BudsDomain

final class NordDualConnectionTests: XCTestCase {
    func testQueryAndPhoneStateFrames() {
        XCTAssertEqual(NordDualConnection.queryDevices(sequence: 7).command, 0x0112)
        XCTAssertEqual(NordDualConnection.followup(enabled: true, sequence: 8).payload,
                       [0x08, 0, 0])
        XCTAssertEqual(NordDualConnection.followup(enabled: false, sequence: 9).payload,
                       [0x08, 0, 1])
    }

    func testDeviceListReplyAndPush() throws {
        let entry: [UInt8] = [6, 5, 4, 3, 2, 1, 5, 2, 7, 4] + Array("Test".utf8)
        let reply = WasiiBudsFrame(command: 0x8112, sequence: 1,
                                   payload: [0, 1] + entry)
        let device = try XCTUnwrap(NordDualConnection.devices(from: reply)?.first)
        XCTAssertEqual(device.id, "01:02:03:04:05:06")
        XCTAssertEqual(device.name, "Test")
        XCTAssertTrue(device.connected)
        XCTAssertTrue(device.thisPhone)
        XCTAssertTrue(device.mainAudio)
        XCTAssertTrue(device.playing)

        let push = WasiiBudsFrame(command: 0x0204, sequence: 0xFF,
                                  payload: [6, 1] + entry)
        XCTAssertEqual(NordDualConnection.devices(from: push), [device])
    }

    func testMalformedDeviceListIsRejected() {
        XCTAssertNil(NordDualConnection.devices(from: .init(command: 0x8112, sequence: 1,
                                                             payload: [1, 1])))
        XCTAssertNil(NordDualConnection.devices(from: .init(command: 0x8112, sequence: 1,
                                                             payload: [0, 1, 6, 5])))
        XCTAssertNil(NordDualConnection.devices(from: .init(command: 0x0204, sequence: 1,
                                                             payload: [5, 0])))
    }
}
