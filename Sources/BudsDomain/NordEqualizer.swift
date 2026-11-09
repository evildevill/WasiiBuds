import Foundation

/// Model 064414's `eqPresets` slots. The ids are device slots, not mode numbers.
public enum NordEQPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case balanced = 3
    case clearVocals = 4
    case bass = 5

    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .balanced: "Balanced"
        case .clearVocals: "Clear Vocals"
        case .bass: "Bass"
        }
    }
}

public struct EQCapabilities: Equatable, Sendable {
    public let builtIn: Bool
    public let custom: Bool
    public let bassWave: Bool

    public init(builtIn: Bool, custom: Bool, bassWave: Bool) {
        self.builtIn = builtIn
        self.custom = custom
        self.bassWave = bassWave
    }
}

public struct CustomEQPreset: Equatable, Identifiable, Sendable {
    public let id: UInt8
    public var name: String
    public let frequencies: [UInt16]
    public var gains: [Int8]
    public let tag: [UInt8]
    public let selected: Bool

    public init(id: UInt8, name: String, frequencies: [UInt16], gains: [Int8],
                tag: [UInt8], selected: Bool) {
        self.id = id
        self.name = name
        self.frequencies = frequencies
        self.gains = gains
        self.tag = tag
        self.selected = selected
    }

    public static func new(name: String) -> Self {
        let frequencies: [UInt16] = [62, 250, 1000, 4000, 8000, 16000]
        return .init(id: 0, name: name, frequencies: frequencies,
                     gains: Array(repeating: 0, count: frequencies.count),
                     tag: [0xFA, 0x06], selected: false)
    }
}

public enum NordEqualizer {
    public enum CustomAction: UInt8, Sendable { case create = 1, save = 2, delete = 3 }

    /// `0x8100` is the hello reply. Bits 10, 34 and 38 gate EQ commands.
    public static func capabilities(from frame: WasiiBudsFrame) -> EQCapabilities? {
        guard frame.command == 0x8100, frame.payload.count >= 2,
              frame.payload[0] == 0 else { return nil }
        let bytes = frame.payload.dropFirst()
        func has(_ bit: Int) -> Bool {
            guard bit / 8 < bytes.count else { return false }
            return bytes[bytes.startIndex + bit / 8] & (1 << (bit % 8)) != 0
        }
        return .init(builtIn: has(10), custom: has(34), bassWave: has(38))
    }

    public static func queryCurrent(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x010F, sequence: sequence, payload: [])
    }

    public static func queryCustom(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0122, sequence: sequence, payload: [])
    }

    public static func selectBuiltIn(_ preset: NordEQPreset, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0406, sequence: sequence, payload: [preset.rawValue])
    }

    public static func current(from frame: WasiiBudsFrame) -> UInt8? {
        if frame.command == 0x810F, frame.payload.count >= 2, frame.payload[0] == 0 {
            return frame.payload[1]
        }
        if frame.command == 0x0504 { return frame.payload.first }
        return nil
    }

    /// WasiiBuds EqCodec: `00 <count> [flag tag0 tag1 id nameLen name bands [freqLE gain]...]`.
    public static func customList(from frame: WasiiBudsFrame) -> [CustomEQPreset]? {
        guard frame.command == 0x8122, frame.payload.count >= 2,
              frame.payload[0] == 0 else { return nil }
        let payload = frame.payload
        let count = Int(payload[1])
        var cursor = 2
        var result: [CustomEQPreset] = []
        for _ in 0..<count {
            guard cursor + 5 <= payload.count else { return nil }
            let selected = payload[cursor] == 1
            let tag = Array(payload[(cursor + 1)...(cursor + 2)])
            let id = payload[cursor + 3]
            let nameLength = Int(payload[cursor + 4])
            cursor += 5
            guard cursor + nameLength + 1 <= payload.count,
                  let name = String(bytes: payload[cursor..<(cursor + nameLength)], encoding: .utf8) else { return nil }
            cursor += nameLength
            let bandCount = Int(payload[cursor])
            cursor += 1
            guard bandCount > 0, bandCount <= 10,
                  cursor + bandCount * 3 <= payload.count else { return nil }
            var frequencies: [UInt16] = []
            var gains: [Int8] = []
            for _ in 0..<bandCount {
                frequencies.append(UInt16(payload[cursor]) | UInt16(payload[cursor + 1]) << 8)
                gains.append(Int8(bitPattern: payload[cursor + 2]))
                cursor += 3
            }
            result.append(.init(id: id, name: name, frequencies: frequencies,
                                gains: gains, tag: tag, selected: selected))
        }
        return result
    }

    public static func custom(_ action: CustomAction, preset: CustomEQPreset,
                              sequence: UInt8) -> WasiiBudsFrame? {
        let name = Array(preset.name.utf8)
        guard !name.isEmpty, name.count <= 20, preset.tag.count == 2,
              preset.frequencies.count == preset.gains.count,
              (1...10).contains(preset.gains.count),
              preset.gains.allSatisfy({ (-6...6).contains(Int($0)) }) else { return nil }
        var payload: [UInt8] = [action.rawValue] + preset.tag +
            [action == .create ? 0 : preset.id, UInt8(name.count)] + name +
            [UInt8(preset.gains.count)]
        for (frequency, gain) in zip(preset.frequencies, preset.gains) {
            payload += [UInt8(frequency & 0xFF), UInt8(frequency >> 8), UInt8(bitPattern: gain)]
        }
        return .init(command: 0x0418, sequence: sequence, payload: payload)
    }

    public static func bassLevelQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0124, sequence: sequence, payload: [])
    }

    public static func bassLevel(_ level: Int, sequence: UInt8) -> WasiiBudsFrame? {
        guard (-5...5).contains(level) else { return nil }
        return .init(command: 0x041B, sequence: sequence,
                     payload: [0xFB, 0x05, UInt8(bitPattern: Int8(level))])
    }

    public static func bassLevel(from frame: WasiiBudsFrame) -> Int? {
        guard frame.command == 0x8124, frame.payload.count >= 4,
              frame.payload[0] == 0 else { return nil }
        let level = Int(Int8(bitPattern: frame.payload[3]))
        return (-5...5).contains(level) ? level : nil
    }
}
