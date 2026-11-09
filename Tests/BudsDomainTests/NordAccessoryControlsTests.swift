import XCTest
@testable import BudsDomain

final class NordAccessoryControlsTests: XCTestCase {
    func testFirmwareReplyUsesMainVersionsByDevice() {
        let text = Array("1,2,138,2,2,139,3,1,01,3,2,105".utf8)
        let reply = WasiiBudsFrame(command: 0x8105, sequence: 7, payload: [0, 4] + text)
        XCTAssertEqual(NordAccessoryControls.firmwareQuery(sequence: 7).command, 0x0105)
        XCTAssertEqual(NordAccessoryControls.firmware(from: reply),
                       .init(left: "138", right: "139", caseVersion: "105"))
        XCTAssertNil(NordAccessoryControls.firmware(from: .init(command: 0x8105,
                                                                 sequence: 7, payload: [1, 4] + text)))
        XCTAssertNil(NordAccessoryControls.firmware(from: .init(command: 0x8105,
                                                                 sequence: 7, payload: [0, 1, 0xFF])))
    }

    func testCallGestureReadbackRequiresBothSides() throws {
        let table = try XCTUnwrap(NordGesture.table(from: .init(command: 0x8108, sequence: 5,
            payload: [0, 2, 1, 6, 2, 0x1D, 2, 6, 2, 0x1D])))
        XCTAssertEqual(table.callFunction(action: 2), 0x1D)
        let mismatched = GestureTable(bindings: [GestureBinding(side: 1, button: 6, action: 2, function: 0x1D),
                                                  GestureBinding(side: 2, button: 6, action: 2, function: 0)])
        XCTAssertNil(mismatched.callFunction(action: 2))
    }

    func testCapabilityGatesAndAccessoryFrames() {
        var bitmap = [UInt8](repeating: 0, count: 4)
        for bit in [3, 5, 9, 22, 26] { bitmap[bit / 8] |= 1 << (bit % 8) }
        let hello = WasiiBudsFrame(command: 0x8100, sequence: 1, payload: [0] + bitmap)
        XCTAssertEqual(NordAccessoryControls.capabilities(from: hello),
                       .init(gestures: true, find: true, fitTest: true,
                             personalANC: true, batchSubscribe: true))
        bitmap[19 / 8] |= 1 << (19 % 8)
        let withHearingTones = WasiiBudsFrame(command: 0x8100, sequence: 2,
                                              payload: [0] + bitmap)
        XCTAssertEqual(NordAccessoryControls.capabilities(from: withHearingTones)?.hearingTest, true)
        XCTAssertEqual(NordAccessoryControls.findTone(true, sequence: 2).payload, [1])
        XCTAssertEqual(NordAccessoryControls.findTone(false, sequence: 3).command, 0x0400)
        XCTAssertEqual(NordAccessoryControls.fitTest(true, sequence: 4).payload, [1])
        XCTAssertEqual(NordAccessoryControls.applyPersonalANC(sequence: 5).payload, [2])
        XCTAssertEqual(NordAccessoryControls.personalStored(from: .init(command: 0x811A,
                                                                         sequence: 1,
                                                                         payload: [0, 1])), true)
        XCTAssertNil(NordAccessoryControls.personalStored(from: .init(command: 0x811A,
                                                                       sequence: 1,
                                                                       payload: [1, 1])))
    }

    func testOnlyOfferedEventsAreSubscribed() {
        let offered = WasiiBudsFrame(command: 0x8200, sequence: 1, payload: [0, 2, 2, 1])
        XCTAssertEqual(NordAccessoryControls.offeredEvents(from: offered), Set([1, 2]))
        XCTAssertNil(NordAccessoryControls.offeredEvents(from: .init(command: 0x8200,
                                                                     sequence: 1,
                                                                     payload: [0, 3, 2, 1])))
        XCTAssertEqual(NordAccessoryControls.subscribe([1, 2], sequence: 2).payload, [2, 1, 2])
        XCTAssertEqual(NordAccessoryControls.subscribeOne(1, sequence: 3).command, 0x0201)
        let reverse = WasiiBudsFrame(command: 0x0204, sequence: 0xFF,
                                     payload: [4, 2, 6, 1, 1])
        XCTAssertEqual(NordAccessoryControls.fitResult(from: reverse)?.left, 1)
        XCTAssertEqual(NordAccessoryControls.fitResult(from: reverse)?.right, 6)
    }

    func testGestureWritePreservesUnchangedAndOnCallBindings() throws {
        let payload: [UInt8] = [0, 4,
                                1, 1, 2, 1,
                                1, 6, 2, 0x1D,
                                2, 1, 2, 5,
                                2, 1, 6, 0x0B]
        let frame = WasiiBudsFrame(command: 0x8108, sequence: 1, payload: payload)
        let original = try XCTUnwrap(NordGesture.table(from: frame))
        let changed = try XCTUnwrap(original.changing(side: 1, action: 2, to: 6))
        XCTAssertEqual(changed.function(side: 1, action: 2), 6)
        XCTAssertTrue(changed.confirms(side: 1, action: 2, function: 6))
        XCTAssertFalse(original.confirms(side: 1, action: 2, function: 6))
        XCTAssertEqual(changed.function(side: 2, action: 2), 5)
        XCTAssertEqual(changed.bindings[1].function, 0x1D)
        XCTAssertEqual(NordGesture.write(changed, sequence: 2)?.payload,
                       [4, 1, 1, 2, 6, 1, 6, 2, 0x1D, 2, 1, 2, 5, 2, 1, 6, 0x0B])
        XCTAssertNil(original.changing(side: 1, action: 2, to: 0xFF))
        XCTAssertNil(original.changing(side: 1, action: 3, to: 0))
    }

    func testMalformedGestureTableIsRejected() {
        XCTAssertNil(NordGesture.table(from: .init(command: 0x8108, sequence: 1,
                                                   payload: [0, 2, 1, 1, 2, 1])))
        XCTAssertNil(NordGesture.table(from: .init(command: 0x8108, sequence: 1,
                                                   payload: [1, 1, 1, 1, 2, 1])))
    }

    func testHoldCycleUsesSetBitsAndReadback() {
        XCTAssertEqual(NordGesture.holdCycleQuery(sequence: 1).payload, [2, 1])
        XCTAssertEqual(NordGesture.holdCycleWrite(mask: 7, sequence: 2)?.payload,
                       [2, 1, 7])
        XCTAssertEqual(NordGesture.holdCycleMask(from: .init(command: 0x810C,
                                                             sequence: 1,
                                                             payload: [0, 2, 1, 7])), 7)
        XCTAssertEqual(NordGesture.holdCycleMask(from: .init(command: 0x0204,
                                                             sequence: 0xFF,
                                                             payload: [3, 2, 1, 7])), 7)
        XCTAssertNil(NordGesture.holdCycleWrite(mask: 0, sequence: 1))
        XCTAssertNil(NordGesture.holdCycleMask(from: .init(command: 0x810C,
                                                           sequence: 1,
                                                           payload: [0, 1, 1, 7])))
    }
}
