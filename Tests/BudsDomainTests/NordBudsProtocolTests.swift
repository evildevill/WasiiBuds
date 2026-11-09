import XCTest
@testable import BudsDomain

final class NordBudsProtocolTests: XCTestCase {
    func testNordTimeRequestUsesRequestSequenceAndLittleEndianSeconds() {
        let request = WasiiBudsFrame(command: 0x0500, sequence: 0x37,
                                     payload: [0, 0, 0, 0])
        let answer = NordBudsProtocol.answerTimeRequest(request, unixSeconds: 0x12345678)
        XCTAssertEqual(answer?.command, 0x8500)
        XCTAssertEqual(answer?.sequence, 0x37)
        XCTAssertEqual(answer?.payload, [0, 0x78, 0x56, 0x34, 0x12])
        XCTAssertNil(NordBudsProtocol.answerTimeRequest(
            .init(command: 0x0501, sequence: 0x37, payload: []), unixSeconds: 0))
    }
    func testGoldenPacketsAndFragmentedReplies() throws {
        XCTAssertEqual(NordBudsProtocol.hello(sequence: 1).encoded(),
                       [0xAA, 7, 0, 0, 0, 1, 1, 0, 0])
        XCTAssertEqual(NordBudsProtocol.setANC(.medium, sequence: 6)?.encoded(),
                       [0xAA, 0x0A, 0, 0, 4, 4, 6, 3, 0, 1, 1, 0x20])
        let packet = WasiiBudsFrame(command: 0x8106, sequence: 7,
                                    payload: [0, 3, 1, 88, 2, 75, 3, 60]).encoded()
        var stream = WasiiBudsStream()
        XCTAssertTrue(stream.append(Array(packet.prefix(6))).isEmpty)
        let received = stream.append(Array(packet.dropFirst(6)))
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(NordBudsProtocol.battery(from: try XCTUnwrap(received.first)),
                       BudBattery(left: 88, right: 75, caseLevel: 60))
    }

    func testModelSpecificANCModeReadback() {
        XCTAssertEqual(NordBudsProtocol.setANC(.transparency, sequence: 2)?.payload, [1, 1, 4])
        XCTAssertEqual(NordBudsProtocol.setANC(.off, sequence: 2)?.payload, [1, 1, 1])
        XCTAssertEqual(NordBudsProtocol.setANC(.deep, sequence: 2)?.payload, [1, 1, 0x10])
        XCTAssertEqual(NordBudsProtocol.anc(from: .init(command: 0x810C, sequence: 2,
                                                        payload: [0, 1, 1, 0, 1])), .transparency)
        XCTAssertEqual(NordBudsProtocol.anc(from: .init(command: 0x0204, sequence: 0xFF,
                                                        payload: [3, 1, 1, 8, 0])), .off)
        XCTAssertNil(NordBudsProtocol.anc(from: .init(command: 0x0204, sequence: 0xFF,
                                                     payload: [3, 2, 1, 8, 0])))
    }

    func testBatteryChargingFlagsAndMissingCase() {
        let openCase = WasiiBudsFrame(command: 0x8106, sequence: 3,
                                      payload: [0, 3, 1, 80, 2, 0x80 | 70, 3, 0x80 | 60])
        XCTAssertEqual(
            NordBudsProtocol.battery(from: openCase),
            BudBattery(left: 80, right: 70, caseLevel: 60,
                       rightCharging: true, caseCharging: true)
        )

        let closedCase = WasiiBudsFrame(command: 0x8106, sequence: 4,
                                        payload: [0, 2, 1, 80, 2, 70])
        let result = NordBudsProtocol.battery(from: closedCase)
        XCTAssertEqual(result?.left, 80)
        XCTAssertEqual(result?.right, 70)
        XCTAssertNil(result?.caseLevel)
        XCTAssertFalse(result?.caseCharging ?? true)
    }

    func testFeatureCommandsAndModelStatusList() {
        XCTAssertEqual(NordBudsProtocol.featureQuery(sequence: 0xC0).payload,
                       [9, 0x05, 0x04, 0x0B, 0x0C, 0x11, 0x18, 0x06, 0x1B, 0x1D])
        XCTAssertEqual(NordBudsProtocol.setFeature(.lowLatency, enabled: true, sequence: 2).payload,
                       [0x06, 1])
        XCTAssertEqual(NordBudsProtocol.setFeature(.dualConnection, enabled: true, sequence: 4).payload,
                       [0x11, 1])
        XCTAssertEqual(NordBudsProtocol.setFeature(.highQuality, enabled: false, sequence: 3).command,
                       0x0403)
    }

    func testFeatureReadbackPushAndMissingID() {
        let reply = WasiiBudsFrame(command: 0x810D, sequence: 7,
                                   payload: [0, 3, 0x06, 1, 0x18, 0, 0x11, 1])
        XCTAssertEqual(NordBudsProtocol.features(from: reply),
                       [.lowLatency: true, .highQuality: false, .dualConnection: true])
        XCTAssertNil(NordBudsProtocol.features(from: .init(command: 0x810D, sequence: 7,
                                                            payload: [1, 1, 0x06, 1])))
        XCTAssertNil(NordBudsProtocol.features(from: .init(command: 0x810D, sequence: 7,
                                                            payload: [0, 2, 0x06, 1])))
        XCTAssertEqual(NordBudsProtocol.features(from: .init(command: 0x0503, sequence: 0xFF,
                                                               payload: [1, 0x1B, 1])), [.spatial: true])
        XCTAssertEqual(NordBudsProtocol.gameMode(from: .init(command: 0x0204, sequence: 0xFF,
                                                              payload: [5, 0])), false)
    }

    func testMutuallyExclusiveSoundSettingsUseVendorWriteOrder() {
        XCTAssertEqual(NordBudsProtocol.featureWrites(for: .highQuality, enabled: true,
                                                       current: [.spatial: true]),
                       [FeatureWrite(.spatial, false), FeatureWrite(.highQuality, true)])
        XCTAssertEqual(NordBudsProtocol.featureWrites(for: .spatial, enabled: true,
                                                       current: [.highQuality: true]),
                       [FeatureWrite(.spatial, true), FeatureWrite(.highQuality, false)])
        XCTAssertEqual(NordBudsProtocol.featureWrites(for: .lowLatency, enabled: false,
                                                       current: [.lowLatency: true]),
                       [FeatureWrite(.lowLatency, false)])
    }
}
