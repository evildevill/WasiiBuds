import XCTest
@testable import BudsDomain

final class WasiiBudsFrameTests: XCTestCase {
    func testCapturedHandshakeAndANCPush() throws {
        let handshake = try WasiiBudsFrame.parse([0xAA, 0x07, 0, 0, 0, 1, 1, 0, 0])
        XCTAssertEqual(handshake.command, 0x0100)
        XCTAssertEqual(handshake.sequence, 1)
        XCTAssertTrue(handshake.payload.isEmpty)

        let push = try WasiiBudsFrame.parse([0xAA, 0x0C, 0, 0, 4, 2, 0xFF, 5, 0, 3, 1, 1, 8, 0])
        XCTAssertEqual(push.command, 0x0204)
        XCTAssertEqual(push.sequence, 0xFF)
        XCTAssertEqual(push.payload, [3, 1, 1, 8, 0])
    }

    func testBadLengthAndSlicedFrameAreRejected() {
        XCTAssertThrowsError(try WasiiBudsFrame.parse([0xAA, 0x07, 0, 0, 0, 1]))
        XCTAssertThrowsError(try WasiiBudsFrame.parse([0xAA, 0x07, 1, 0, 0, 1, 1, 0, 0]))
    }

    func testSlicedEarScanReassemblesAcrossNotifications() {
        let scan = [UInt8](repeating: 0xA5, count: 168)
        let payload: [UInt8] = [0x0E, 3, 168, 0] + scan + [0x12, 0x34, 0x56, 0x78]
        let message: [UInt8] = [4, 2, 0xFF, UInt8(payload.count), 0] + payload
        func slice(_ kind: UInt8, _ number: UInt8, _ data: [UInt8]) -> [UInt8] {
            [0xAA, UInt8(data.count + 3), kind, 0, number] + data
        }
        let slices = slice(1, 0, Array(message[0..<60])) +
            slice(2, 1, Array(message[60..<120])) +
            slice(3, 2, Array(message[120...]))
        var stream = WasiiBudsStream()
        XCTAssertTrue(stream.append(Array(slices[0..<23])).isEmpty)
        XCTAssertTrue(stream.append(Array(slices[23..<110])).isEmpty)
        let frames = stream.append(Array(slices[110...]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames.first?.command, 0x0204)
        XCTAssertEqual(NordHearingProfile.scan(from: frames[0])?.id, 0x12345678)
        XCTAssertEqual(NordHearingProfile.scan(from: frames[0])?.data, scan)
    }
}
