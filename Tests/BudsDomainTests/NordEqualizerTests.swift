import XCTest
@testable import BudsDomain

final class NordEqualizerTests: XCTestCase {
    func testModelPresetSlotsAndReadback() {
        XCTAssertEqual(NordEqualizer.selectBuiltIn(.balanced, sequence: 2).payload, [3])
        XCTAssertEqual(NordEqualizer.selectBuiltIn(.clearVocals, sequence: 3).payload, [4])
        XCTAssertEqual(NordEqualizer.selectBuiltIn(.bass, sequence: 4).payload, [5])
        XCTAssertEqual(NordEqualizer.current(from: .init(command: 0x810F, sequence: 2,
                                                          payload: [0, 4])), 4)
        XCTAssertEqual(NordEqualizer.current(from: .init(command: 0x0504, sequence: 0xFF,
                                                          payload: [5])), 5)
        XCTAssertNil(NordEqualizer.current(from: .init(command: 0x810F, sequence: 2,
                                                       payload: [1, 4])))
    }

    func testBitmapGatesCommands() {
        var bitmap = [UInt8](repeating: 0, count: 5)
        bitmap[1] |= 1 << 2 // bit 10: built-in EQ
        bitmap[4] |= 1 << 2 // bit 34: custom EQ
        let frame = WasiiBudsFrame(command: 0x8100, sequence: 1, payload: [0] + bitmap)
        XCTAssertEqual(NordEqualizer.capabilities(from: frame),
                       EQCapabilities(builtIn: true, custom: true, bassWave: false))
        XCTAssertNil(NordEqualizer.capabilities(from: .init(command: 0x8100, sequence: 1,
                                                            payload: [1, 0xFF])))
    }

    func testCustomPresetRoundTripAndMalformedReply() throws {
        var preset = CustomEQPreset.new(name: "Custom 1")
        preset.gains = [-6, -2, 0, 3, 5, 6]
        let save = try XCTUnwrap(NordEqualizer.custom(.save, preset: preset, sequence: 7))
        XCTAssertEqual(save.command, 0x0418)
        XCTAssertEqual(save.payload.prefix(4), [2, 0xFA, 6, 0])
        let list = WasiiBudsFrame(command: 0x8122, sequence: 8,
                                  payload: [0, 1, 1] + Array(save.payload.dropFirst()))
        XCTAssertEqual(NordEqualizer.customList(from: list), [
            .init(id: 0, name: "Custom 1", frequencies: preset.frequencies,
                  gains: preset.gains, tag: [0xFA, 6], selected: true)
        ])
        XCTAssertNil(NordEqualizer.customList(from: .init(command: 0x8122, sequence: 8,
                                                           payload: [0, 1, 1, 0xFA])))
    }

    func testBassWaveRangeAndSignedLevel() {
        XCTAssertEqual(NordEqualizer.bassLevel(-5, sequence: 2)?.payload, [0xFB, 5, 0xFB])
        XCTAssertNil(NordEqualizer.bassLevel(6, sequence: 2))
        XCTAssertEqual(NordEqualizer.bassLevel(from: .init(command: 0x8124, sequence: 2,
                                                            payload: [0, 0xFB, 5, 0xFD])), -3)
        XCTAssertEqual(NordEqualizer.bassLevel(from: .init(command: 0x8124, sequence: 2,
                                                            payload: [0, 0, 0, 2])), 2)
    }
}
