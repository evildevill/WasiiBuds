import Foundation

public struct AccessoryCapabilities: Equatable, Sendable {
    public let firmware: Bool
    public let gestures: Bool
    public let find: Bool
    public let fitTest: Bool
    public let hearingTest: Bool
    public let hearingScan: Bool
    public let personalANC: Bool
    public let batchSubscribe: Bool

    public init(firmware: Bool = false, gestures: Bool, find: Bool, fitTest: Bool, hearingTest: Bool = false,
                hearingScan: Bool = false, personalANC: Bool, batchSubscribe: Bool) {
        self.firmware = firmware
        self.gestures = gestures
        self.find = find
        self.fitTest = fitTest
        self.hearingTest = hearingTest
        self.hearingScan = hearingScan
        self.personalANC = personalANC
        self.batchSubscribe = batchSubscribe
    }
}

public enum NordAccessoryControls {
    public static func firmwareQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0105, sequence: sequence, payload: [])
    }

    public static func firmware(from frame: WasiiBudsFrame) -> FirmwareDetails? {
        guard frame.command == 0x8105, frame.payload.count >= 2,
              frame.payload[0] == 0,
              let text = String(bytes: frame.payload.dropFirst(2), encoding: .utf8) else { return nil }
        let fields = text.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !fields.isEmpty, fields.count.isMultiple(of: 3) else { return nil }
        var versions: [UInt8: String] = [:]
        for index in stride(from: 0, to: fields.count, by: 3) {
            guard let device = UInt8(fields[index]), let kind = UInt8(fields[index + 1]),
                  !fields[index + 2].isEmpty else { return nil }
            if kind == 2, (1...3).contains(device) { versions[device] = fields[index + 2] }
        }
        guard !versions.isEmpty else { return nil }
        return FirmwareDetails(left: versions[1], right: versions[2], caseVersion: versions[3])
    }

    public static func fitResult(from frame: WasiiBudsFrame) -> (left: UInt8, right: UInt8)? {
        guard frame.command == 0x0204, frame.payload.count >= 5,
              frame.payload[0] == 4 else { return nil }
        var left: UInt8?
        var right: UInt8?
        for index in stride(from: 1, through: 3, by: 2) {
            if frame.payload[index] == 1 { left = frame.payload[index + 1] }
            if frame.payload[index] == 2 { right = frame.payload[index + 1] }
        }
        guard let left, let right else { return nil }
        return (left, right)
    }

    public static func offeredEventsQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0200, sequence: sequence, payload: [])
    }

    public static func offeredEvents(from frame: WasiiBudsFrame) -> Set<UInt8>? {
        guard frame.command == 0x8200, frame.payload.count >= 2, frame.payload[0] == 0,
              frame.payload.count == 2 + Int(frame.payload[1]) else { return nil }
        return Set(frame.payload.dropFirst(2))
    }

    public static func subscribe(_ events: [UInt8], sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0205, sequence: sequence,
              payload: [UInt8(events.count)] + events)
    }

    public static func subscribeOne(_ event: UInt8, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0201, sequence: sequence, payload: [event])
    }

    public static func capabilities(from frame: WasiiBudsFrame) -> AccessoryCapabilities? {
        guard frame.command == 0x8100, frame.payload.first == 0 else { return nil }
        let bits = Array(frame.payload.dropFirst())
        func has(_ bit: Int) -> Bool {
            bit / 8 < bits.count && bits[bit / 8] & (1 << (bit % 8)) != 0
        }
        return .init(firmware: has(0), gestures: has(3), find: has(5), fitTest: has(9),
                     hearingTest: has(19), hearingScan: has(30) && has(31),
                     personalANC: has(26), batchSubscribe: has(22))
    }

    public static func findTone(_ enabled: Bool, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0400, sequence: sequence, payload: [enabled ? 1 : 0])
    }

    public static func fitTest(_ enabled: Bool, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0405, sequence: sequence, payload: [enabled ? 1 : 0])
    }

    public static func personalStoredQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x011A, sequence: sequence, payload: [])
    }

    public static func personalStored(from frame: WasiiBudsFrame) -> Bool? {
        guard frame.command == 0x811A, frame.payload.count >= 2,
              frame.payload[0] == 0 else { return nil }
        return frame.payload[1] != 0
    }

    public static func applyPersonalANC(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0412, sequence: sequence, payload: [2])
    }
}

public struct FirmwareDetails: Equatable, Sendable {
    public let left: String?
    public let right: String?
    public let caseVersion: String?
    public init(left: String?, right: String?, caseVersion: String?) {
        self.left = left
        self.right = right
        self.caseVersion = caseVersion
    }
}

public struct GestureBinding: Equatable, Sendable {
    public let side: UInt8
    public let button: UInt8
    public let action: UInt8
    public var function: UInt8

    public init(side: UInt8, button: UInt8, action: UInt8, function: UInt8) {
        self.side = side
        self.button = button
        self.action = action
        self.function = function
    }
}

public struct GestureTable: Equatable, Sendable {
    public var bindings: [GestureBinding]

    public init(bindings: [GestureBinding]) { self.bindings = bindings }

    public func function(side: UInt8, action: UInt8) -> UInt8? {
        bindings.first { $0.side == side && $0.button != 6 && $0.action == action }?.function
    }

    public func confirms(side: UInt8, action: UInt8, function: UInt8) -> Bool {
        let matching = bindings.filter { $0.side == side && $0.button != 6 && $0.action == action }
        return !matching.isEmpty && matching.allSatisfy { $0.function == function }
    }

    public func callFunction(action: UInt8) -> UInt8? {
        let values = bindings.filter { ($0.side == 1 || $0.side == 2) &&
            $0.button == 6 && $0.action == action }.map(\.function)
        guard values.count == 2, values[0] == values[1] else { return nil }
        return values[0]
    }

    /// A full-table write preserves slots unknown to this app, including call bindings.
    public func changing(side: UInt8, action: UInt8, to function: UInt8) -> Self? {
        guard side == 1 || side == 2,
              NordGesture.availableActions(for: action).contains(where: { $0.function == function }) else { return nil }
        var updated = bindings
        var matched = false
        for index in updated.indices where updated[index].side == side &&
            updated[index].button != 6 && updated[index].action == action {
            updated[index].function = function
            matched = true
        }
        return matched ? .init(bindings: updated) : nil
    }
}

public struct GestureChoice: Equatable, Identifiable, Sendable {
    public let title: String
    public let function: UInt8
    public var id: UInt8 { function }
    public init(_ title: String, _ function: UInt8) {
        self.title = title
        self.function = function
    }
}

public enum NordGesture {
    public static func holdCycleQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x010C, sequence: sequence, payload: [2, 1])
    }

    public static func holdCycleMask(from frame: WasiiBudsFrame) -> UInt32? {
        let bytes: [UInt8]
        if frame.command == 0x810C {
            guard frame.payload.count >= 4, frame.payload[0...2] == [0, 2, 1] else { return nil }
            bytes = Array(frame.payload.dropFirst(3))
        } else if frame.command == 0x0204 {
            guard frame.payload.count >= 4, frame.payload[0...2] == [3, 2, 1] else { return nil }
            bytes = Array(frame.payload.dropFirst(3))
        } else { return nil }
        guard bytes.count <= 4 else { return nil }
        return bytes.enumerated().reduce(UInt32(0)) { value, element in
            value | UInt32(element.element) << (element.offset * 8)
        }
    }

    public static func holdCycleWrite(mask: UInt32, sequence: UInt8) -> WasiiBudsFrame? {
        guard mask != 0 else { return nil }
        var bytes: [UInt8] = []
        var value = mask
        repeat {
            bytes.append(UInt8(truncatingIfNeeded: value))
            value >>= 8
        } while value != 0
        return .init(command: 0x0404, sequence: sequence, payload: [2, 1] + bytes)
    }

    public static func query(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0108, sequence: sequence, payload: [])
    }

    public static func table(from frame: WasiiBudsFrame) -> GestureTable? {
        guard frame.command == 0x8108, frame.payload.count >= 2,
              frame.payload[0] == 0 else { return nil }
        let count = Int(frame.payload[1])
        guard count > 0, count <= 64, frame.payload.count == 2 + count * 4 else { return nil }
        let bindings = (0..<count).map { index in
            let start = 2 + index * 4
            return GestureBinding(side: frame.payload[start], button: frame.payload[start + 1],
                                  action: frame.payload[start + 2], function: frame.payload[start + 3])
        }
        return .init(bindings: bindings)
    }

    public static func write(_ table: GestureTable, sequence: UInt8) -> WasiiBudsFrame? {
        guard table.bindings.count <= 64 else { return nil }
        let payload = [UInt8(table.bindings.count)] + table.bindings.flatMap {
            [$0.side, $0.button, $0.action, $0.function]
        }
        return .init(command: 0x0401, sequence: sequence, payload: payload)
    }

    /// Model 064414's masks: 516, 8807, 8803 and 536. Hold ANC cycle is a separate command.
    public static func availableActions(for action: UInt8) -> [GestureChoice] {
        let all = [GestureChoice("None", 0), GestureChoice("Play / pause", 1),
                   GestureChoice("Voice assistant", 3), GestureChoice("Previous track", 5),
                   GestureChoice("Next track", 6), GestureChoice("Volume up", 0x0B),
                   GestureChoice("Volume down", 0x0C), GestureChoice("Game mode", 0x11)]
        let mask: Int = switch action {
        case 1: 516
        case 2: 8807
        case 3: 8803
        case 6: 536
        default: 0
        }
        let bits: [UInt8: Int] = [0: 512, 1: 4, 3: 1, 5: 32, 6: 64,
                                  0x0B: 8, 0x0C: 16, 0x11: 8192]
        return all.filter { mask & (bits[$0.function] ?? 0) != 0 }
    }
}
