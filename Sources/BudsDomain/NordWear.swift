public enum EarPresence: Equatable, Sendable {
    case inEar
    case outOfEar
    case inCase

    public var title: String {
        switch self {
        case .inEar: "In ear"
        case .outOfEar: "Out of ear"
        case .inCase: "In case"
        }
    }
}

public struct WearReport: Equatable, Sendable {
    public let left: EarPresence?
    public let right: EarPresence?

    public init(left: EarPresence?, right: EarPresence?) {
        self.left = left
        self.right = right
    }
}

public enum NordWear {
    public static func query(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0109, sequence: sequence, payload: [])
    }

    public static func report(from frame: WasiiBudsFrame) -> WearReport? {
        if frame.command == 0x8109 {
            return parse(frame.payload, offsets: [0, 1])
        }
        if frame.command == 0x0204, frame.payload.first == 2 {
            return parse(frame.payload, offsets: [1])
        }
        return nil
    }

    private static func parse(_ payload: [UInt8], offsets: [Int]) -> WearReport? {
        for offset in offsets {
            guard payload.count > offset else { continue }
            let count = Int(payload[offset])
            guard count > 0, count <= 8, payload.count >= offset + 1 + count * 2 else { continue }
            var left: EarPresence?
            var right: EarPresence?
            var valid = true
            for index in 0..<count {
                let part = payload[offset + 1 + index * 2]
                let raw = payload[offset + 2 + index * 2]
                guard part >= 1 && part <= 3, raw <= 15 else { valid = false; break }
                let state = raw & 0x07
                let presence: EarPresence
                if state & 1 == 0 { presence = .inCase }
                else if state & 2 != 0 { presence = .inEar }
                else { presence = .outOfEar }
                if part == 1 { left = presence }
                if part == 2 { right = presence }
            }
            if valid, left != nil || right != nil { return .init(left: left, right: right) }
        }
        return nil
    }
}
