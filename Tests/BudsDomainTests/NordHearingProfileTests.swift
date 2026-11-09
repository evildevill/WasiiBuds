import XCTest
@testable import BudsDomain

final class NordHearingProfileTests: XCTestCase {
    func testActiveRecordAndScanReplies() {
        let values = (0..<12).map { Int8($0 - 6) }
        let info = values.enumerated().flatMap { index, value in
            [UInt8(index / 6 + 1), UInt8(index % 6 + 1), UInt8(bitPattern: value)]
        }
        let active = WasiiBudsFrame(command: 0x8115, sequence: 1,
                                    payload: [0, 3, 12] + info + [0x12, 0x34, 0x56, 0x78] +
                                        Array("2026/11/08 15:30".utf8))
        let parsed = NordHearingProfile.active(from: active)
        XCTAssertEqual(parsed?.id, 0x12345678)
        XCTAssertEqual(parsed?.values, values)
        XCTAssertEqual(parsed?.name, "2026/11/08 15:30")

        let scan = [UInt8](repeating: 0xA5, count: 168)
        let event = WasiiBudsFrame(command: 0x0204, sequence: 2,
                                   payload: [0x0E, 3, 168, 0] + scan +
                                       [0x12, 0x34, 0x56, 0x78])
        XCTAssertEqual(NordHearingProfile.scan(from: event)?.id, 0x12345678)
        XCTAssertEqual(NordHearingProfile.scan(from: event)?.data, scan)
        XCTAssertEqual(try? WasiiBudsFrame.parse(event.encoded()), event)
        let alternateAction = WasiiBudsFrame(command: 0x0204, sequence: 3,
                                             payload: [0x0E, 2, 168, 0] + scan +
                                                 [0x12, 0x34, 0x56, 0x78])
        XCTAssertEqual(NordHearingProfile.scan(from: alternateAction)?.id, 0x12345678)
    }

    func testToneSequenceAndApplyPreserveSignedValues() {
        XCTAssertEqual(NordHearingProfile.snapped(-30), -35)
        XCTAssertEqual(NordHearingProfile.tone(side: 2, frequency: 6, value: -30,
                                                sequence: 4)?.payload,
                       [3, 1, 2, 6, 226])
        let record = HearingProfileRecord(id: 0x01020304, name: "Test",
                                          values: [Int8](repeating: -25, count: 12),
                                          scan: [UInt8](repeating: 7, count: 168),
                                          descriptionID: 11)
        var sequence: UInt8 = 10
        let frames = NordHearingProfile.apply(record, sequence: &sequence)
        XCTAssertEqual(frames?.map(\.command), [0x0411, 0x040E, 0x0415, 0x0403])
        XCTAssertEqual(frames?.last?.payload, [0x0B, 1])
        XCTAssertEqual(frames?[1].payload[4], 231)
        XCTAssertEqual(sequence, 14)
        XCTAssertEqual(try? WasiiBudsFrame.parse(frames![2].encoded()), frames![2])
        let toneOnly = HearingProfileRecord(id: record.id, name: record.name,
                                            values: record.values, descriptionID: record.descriptionID)
        var toneOnlySequence: UInt8 = 20
        let toneOnlyFrames = NordHearingProfile.apply(toneOnly, sequence: &toneOnlySequence)
        XCTAssertEqual(toneOnlyFrames?.map(\.command), [0x0411, 0x040E, 0x0403])
    }

    func testMalformedResponsesAreIgnored() {
        XCTAssertNil(NordHearingProfile.active(from:
            .init(command: 0x8115, sequence: 1, payload: [0, 3, 12])))
        XCTAssertNil(NordHearingProfile.scan(from:
            .init(command: 0x0204, sequence: 1, payload: [0x0E, 3, 168, 0])))
        var sequence: UInt8 = 0
        XCTAssertNil(NordHearingProfile.apply(
            .init(id: 1, name: "Bad", values: [0]), sequence: &sequence))
    }
}
