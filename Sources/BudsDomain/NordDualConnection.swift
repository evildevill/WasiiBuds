import Foundation

public struct PairedAudioDevice: Equatable, Identifiable, Sendable {
    /// Reverse of the six bytes in the earbuds' list. Kept in memory only.
    public let id: String
    public let name: String
    public let connected: Bool
    public let thisPhone: Bool
    public let mainAudio: Bool
    public let playing: Bool

    public init(id: String, name: String, connected: Bool,
                thisPhone: Bool, mainAudio: Bool, playing: Bool) {
        self.id = id
        self.name = name
        self.connected = connected
        self.thisPhone = thisPhone
        self.mainAudio = mainAudio
        self.playing = playing
    }
}

public enum NordDualConnection {
    public static func queryDevices(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0112, sequence: sequence, payload: [])
    }

    /// Captured HeyMelody order: feature 0x11, status readback, then this host-state frame.
    public static func followup(enabled: Bool, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0413, sequence: sequence,
              payload: [0x08, 0, enabled ? 0 : 1])
    }

    /// `0x8112`: `00 <count> <entries>`. Active push `0x0204`: `06 <count> <entries>`.
    /// Each entry: reversed MAC(6), entry length, state, flags, name length, name.
    public static func devices(from frame: WasiiBudsFrame) -> [PairedAudioDevice]? {
        let payload = frame.payload
        if frame.command == 0x8112 {
            guard payload.first == 0 else { return nil }
        } else if frame.command == 0x0204 {
            guard payload.first == 0x06 else { return nil }
        } else { return nil }
        guard payload.count >= 2 else { return nil }
        let count = Int(payload[1])
        var cursor = 2
        var result: [PairedAudioDevice] = []
        for _ in 0..<count {
            guard cursor + 10 <= payload.count else { return nil }
            let id = (0..<6).reversed().map {
                String(format: "%02X", payload[cursor + $0])
            }.joined(separator: ":")
            let state = payload[cursor + 7]
            let flags = payload[cursor + 8]
            let nameLength = Int(payload[cursor + 9])
            cursor += 10
            guard cursor + nameLength <= payload.count,
                  let name = String(bytes: payload[cursor..<(cursor + nameLength)], encoding: .utf8) else { return nil }
            cursor += nameLength
            result.append(.init(id: id, name: name.isEmpty ? "Unnamed device" : name,
                                connected: state == 2, thisPhone: flags & 1 != 0,
                                mainAudio: flags & 2 != 0, playing: flags & 4 != 0))
        }
        return result
    }
}
