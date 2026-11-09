import Foundation

public struct HearingProfileRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let name: String
    public let values: [Int8]
    public let scan: [UInt8]
    public let descriptionID: UInt8

    public init(id: UInt32, name: String, values: [Int8], scan: [UInt8] = [],
                descriptionID: UInt8 = 0) {
        self.id = id
        self.name = name
        self.values = values
        self.scan = scan
        self.descriptionID = descriptionID
    }
}

public enum NordHearingProfile {
    public static let stops: [Int8] = [-120, -88, -55, -52, -49, -45, -41, -38, -35,
                                       -30, -25, -22, -19, -15, -11, -8, -5, -1,
                                       3, 5, 7, 10, 13, 15, 17]
    private static let results: [Int8] = [-55, -49, -41, -35, -25, -19, -11, -5,
                                          3, 7, 13, 17]

    public static func snapped(_ value: Int8) -> Int8 {
        results.min(by: { abs(Int($0) - Int(value)) < abs(Int($1) - Int(value)) }) ?? value
    }

    private static func idBytes(_ id: UInt32) -> [UInt8] {
        [UInt8((id >> 24) & 0xFF), UInt8((id >> 16) & 0xFF),
         UInt8((id >> 8) & 0xFF), UInt8(id & 0xFF)]
    }

    private static func readID(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func info(_ values: [Int8]) -> [UInt8]? {
        guard values.count == 12 else { return nil }
        return values.enumerated().flatMap { index, value in
            [UInt8(index / 6 + 1), UInt8(index % 6 + 1), UInt8(bitPattern: value)]
        }
    }

    public static func queryActive(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0115, sequence: sequence, payload: [])
    }

    public static func queryScan(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x011E, sequence: sequence, payload: [])
    }

    public static func active(from frame: WasiiBudsFrame) -> HearingProfileRecord? {
        let payload = frame.payload
        guard frame.command == 0x8115, payload.count >= 43,
              payload[0...2].elementsEqual([0, 3, 12]) else { return nil }
        var values = [Int8](repeating: 0, count: 12)
        for index in 0..<12 {
            let offset = 3 + index * 3
            let side = payload[offset], frequency = payload[offset + 1]
            guard (1...2).contains(side), (1...6).contains(frequency) else { return nil }
            values[Int(side - 1) * 6 + Int(frequency - 1)] = Int8(bitPattern: payload[offset + 2])
        }
        let id = readID(payload, at: 39)
        let name = String(decoding: payload.dropFirst(43), as: UTF8.self)
        return .init(id: id, name: name.isEmpty ? "Profile \(id)" : name, values: values)
    }

    public static func scan(from frame: WasiiBudsFrame) -> (id: UInt32, data: [UInt8])? {
        let payload = frame.payload
        let start: Int
        if frame.command == 0x811E {
            guard payload.first == 0 else { return nil }
            start = 1
        } else if frame.command == 0x0204 {
            guard payload.first == 0x0E else { return nil }
            start = 1
        } else { return nil }
        guard payload.count >= start + 3 else { return nil }
        let count = Int(payload[start + 1]) | Int(payload[start + 2]) << 8
        let dataStart = start + 3
        guard count == 168, payload.count >= dataStart + count + 4 else { return nil }
        return (readID(payload, at: dataStart + count),
                Array(payload[dataStart..<dataStart + count]))
    }

    public static func status(from frame: WasiiBudsFrame) -> (kind: UInt8, code: UInt8)? {
        guard frame.command == 0x0204, frame.payload.count >= 3,
              frame.payload[0] == 8 else { return nil }
        return (frame.payload[1], frame.payload[2])
    }

    public static func enhanceType(from frame: WasiiBudsFrame) -> (id: UInt32, kind: UInt8)? {
        guard frame.command == 0x8116, frame.payload.count >= 10,
              frame.payload[0] == 0, frame.payload[5] == 4 else { return nil }
        return (readID(frame.payload, at: 1), frame.payload[9])
    }

    public static func scanCommand(_ enabled: Bool, id: UInt32, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x040D, sequence: sequence,
              payload: [4, enabled ? 1 : 0] + idBytes(id))
    }

    public static func testCommand(_ enabled: Bool, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x040D, sequence: sequence, payload: [2, enabled ? 1 : 0])
    }

    public static func toneStop(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x040E, sequence: sequence, payload: [4])
    }

    public static func tone(side: UInt8, frequency: UInt8, value: Int8,
                            sequence: UInt8) -> WasiiBudsFrame? {
        guard (1...2).contains(side), (1...6).contains(frequency) else { return nil }
        return .init(command: 0x040E, sequence: sequence,
                     payload: [3, 1, side, frequency, UInt8(bitPattern: value)])
    }

    public static func filter(id: UInt32, values: [Int8], sequence: UInt8) -> WasiiBudsFrame? {
        guard let info = info(values) else { return nil }
        return .init(command: 0x0116, sequence: sequence,
                     payload: [12] + info + idBytes(id))
    }

    public static func apply(_ record: HearingProfileRecord, sequence: inout UInt8) -> [WasiiBudsFrame]? {
        let name = Array(record.name.utf8)
        guard let info = info(record.values), record.scan.isEmpty || record.scan.count == 168,
              name.count <= 40 else { return nil }
        func next() -> UInt8 { defer { sequence &+= 1 }; return sequence }
        var frames: [WasiiBudsFrame] = []
        if record.descriptionID > 0 {
            frames.append(.init(command: 0x0411, sequence: next(),
                                payload: [1, 1, 1, 0, record.descriptionID]))
        }
        frames.append(.init(command: 0x040E, sequence: next(),
                            payload: [3, 12] + info + idBytes(record.id) + name))
        if !record.scan.isEmpty {
            frames.append(.init(command: 0x0415, sequence: next(),
                                payload: [3, 168, 0] + record.scan + idBytes(record.id)))
        }
        frames.append(.init(command: 0x0403, sequence: next(), payload: [0x0B, 1]))
        return frames
    }
}
