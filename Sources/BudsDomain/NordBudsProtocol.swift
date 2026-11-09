import Foundation

public enum ANCMode: String, CaseIterable, Sendable, Identifiable {
    case off = "Off"
    case transparency = "Transparency"
    case light = "Light"
    case medium = "Medium"
    case deep = "Deep"
    case smart = "Smart"
    case anc = "Noise cancelling"

    public var id: String { rawValue }

    /// Slots from WasiiBuds models.json for product 064414.
    public var setBit: Int? {
        switch self {
        case .off: 0
        case .transparency: 2
        case .light: 6
        case .medium: 5
        case .deep: 4
        case .smart: 7
        case .anc: nil
        }
    }

    public static func reported(mask: UInt32) -> Self? {
        guard mask != 0 else { return nil }
        return switch mask.trailingZeroBitCount {
        case 0, 3: .off
        case 2, 8: .transparency
        case 4: .deep
        case 5: .medium
        case 6: .light
        case 7: .smart
        case 1: .anc
        default: nil
        }
    }
}

public struct BudBattery: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var leftCharging: Bool
    public var rightCharging: Bool
    public var caseCharging: Bool

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil,
                leftCharging: Bool = false, rightCharging: Bool = false,
                caseCharging: Bool = false) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.leftCharging = leftCharging
        self.rightCharging = rightCharging
        self.caseCharging = caseCharging
    }
}

public enum BudFeature: UInt8, CaseIterable, Identifiable, Sendable {
    case autoPlayPause = 0x04
    case lowLatency = 0x06
    case hearingProfile = 0x0B
    case personalANC = 0x0C
    case dualConnection = 0x11
    case highQuality = 0x18
    case spatial = 0x1B
    case bassBoost = 0x1D

    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .autoPlayPause: "Auto play / pause"
        case .lowLatency: "Low latency mode"
        case .hearingProfile: "Hearing profile"
        case .personalANC: "Personalized noise cancellation"
        case .dualConnection: "Dual connection"
        case .highQuality: "High-quality audio"
        case .spatial: "3D audio"
        case .bassBoost: "Bass boost"
        }
    }
}

public struct FeatureWrite: Equatable, Sendable {
    public let feature: BudFeature
    public let enabled: Bool

    public init(_ feature: BudFeature, _ enabled: Bool) {
        self.feature = feature
        self.enabled = enabled
    }
}

public enum NordBudsProtocol {
    public static let service = "0000079A-D102-11E1-9B23-00025B00A5A5"
    public static let write = "0100079A-D102-11E1-9B23-00025B00A5A5"
    public static let notify = "0200079A-D102-11E1-9B23-00025B00A5A5"

    public static func hello(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0100, sequence: sequence, payload: [])
    }


    /// Device-specific GATT registration observed on the Nord Buds 3 Pro.
    public static func register() -> WasiiBudsFrame {
        .init(command: 0x8500, sequence: 0x41, payload: [0, 0xB5, 0x50, 0xA0, 0x69])
    }

    /// Nord Buds 3 Pro requests the phone clock during setup. WasiiBuds records
    /// that leaving this request unanswered can make the buds stop replying.
    public static func answerTimeRequest(_ frame: WasiiBudsFrame,
                                         unixSeconds: UInt32) -> WasiiBudsFrame? {
        guard frame.command == 0x0500 else { return nil }
        return .init(command: 0x8500, sequence: frame.sequence,
                     payload: [0, UInt8(truncatingIfNeeded: unixSeconds),
                               UInt8(truncatingIfNeeded: unixSeconds >> 8),
                               UInt8(truncatingIfNeeded: unixSeconds >> 16),
                               UInt8(truncatingIfNeeded: unixSeconds >> 24)])
    }

    public static func batteryQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0106, sequence: sequence, payload: [])
    }

    public static func ancQuery(sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x010C, sequence: sequence, payload: [1, 1])
    }

    /// The nine ids in WasiiBuds' model 064414 statusQuery.
    public static func featureQuery(sequence: UInt8) -> WasiiBudsFrame {
        let ids: [UInt8] = [0x05, 0x04, 0x0B, 0x0C, 0x11, 0x18, 0x06, 0x1B, 0x1D]
        return .init(command: 0x010D, sequence: sequence, payload: [UInt8(ids.count)] + ids)
    }

    public static func setFeature(_ feature: BudFeature, enabled: Bool, sequence: UInt8) -> WasiiBudsFrame {
        .init(command: 0x0403, sequence: sequence, payload: [feature.rawValue, enabled ? 1 : 0])
    }

    /// HeyMelody's order when 3D audio and high-quality audio exclude each other.
    public static func featureWrites(for feature: BudFeature, enabled: Bool,
                                     current: [BudFeature: Bool]) -> [FeatureWrite] {
        if feature == .highQuality && enabled && current[.spatial] == true {
            return [FeatureWrite(.spatial, false), FeatureWrite(.highQuality, true)]
        }
        if feature == .spatial && enabled && current[.highQuality] == true {
            return [FeatureWrite(.spatial, true), FeatureWrite(.highQuality, false)]
        }
        return [FeatureWrite(feature, enabled)]
    }

    /// Returns only the ids actually reported by the firmware. A missing id is unavailable.
    public static func features(from frame: WasiiBudsFrame) -> [BudFeature: Bool]? {
        let payload: [UInt8]
        if frame.command == 0x810D {
            guard frame.payload.first == 0 else { return nil }
            payload = Array(frame.payload.dropFirst())
        } else if frame.command == 0x0503 {
            payload = frame.payload
        } else { return nil }
        guard let count = payload.first, payload.count >= 1 + Int(count) * 2 else { return nil }
        var result: [BudFeature: Bool] = [:]
        for index in 0..<Int(count) {
            let offset = 1 + index * 2
            if let feature = BudFeature(rawValue: payload[offset]) {
                result[feature] = payload[offset + 1] != 0
            }
        }
        return result
    }

    public static func gameMode(from frame: WasiiBudsFrame) -> Bool? {
        guard frame.command == 0x0204, frame.payload.count >= 2,
              frame.payload[0] == 0x05 else { return nil }
        return frame.payload[1] != 0
    }

    public static func setANC(_ mode: ANCMode, sequence: UInt8) -> WasiiBudsFrame? {
        guard let bit = mode.setBit else { return nil }
        var mask = [UInt8](repeating: 0, count: bit / 8 + 1)
        mask[bit / 8] = 1 << (bit % 8)
        return .init(command: 0x0404, sequence: sequence, payload: [1, 1] + mask)
    }

    public static func battery(from frame: WasiiBudsFrame) -> BudBattery? {
        var payload = frame.payload
        if frame.command == 0x8106 {
            guard payload.first == 0 else { return nil }
            payload.removeFirst()
        } else if frame.command == 0x0204 {
            guard payload.first == 1 else { return nil }
            payload.removeFirst()
        } else { return nil }
        guard let first = payload.first, first > 0,
              payload.count >= 1 + Int(first) * 2 else { return nil }
        var result = BudBattery()
        for index in 0..<Int(first) {
            let part = payload[1 + index * 2]
            let raw = payload[2 + index * 2]
            let level = Int(raw & 0x7F)
            guard level > 0, level <= 100 else { continue }
            let charging = raw & 0x80 != 0
            switch part {
            case 1:
                result.left = level
                result.leftCharging = charging
            case 2:
                result.right = level
                result.rightCharging = charging
            case 3:
                result.caseLevel = level
                result.caseCharging = charging
            default: break
            }
        }
        return result
    }

    public static func anc(from frame: WasiiBudsFrame) -> ANCMode? {
        let payload = frame.payload
        let bytes: ArraySlice<UInt8>
        if frame.command == 0x810C {
            guard payload.count >= 4, payload[0...2].elementsEqual([0, 1, 1]) else { return nil }
            bytes = payload.dropFirst(3)
        } else if frame.command == 0x0204 {
            guard payload.count >= 4, payload[0...2].elementsEqual([3, 1, 1]) else { return nil }
            bytes = payload.dropFirst(3)
        } else { return nil }
        let mask = bytes.prefix(4).enumerated().reduce(UInt32(0)) { result, item in
            result | UInt32(item.element) << (8 * item.offset)
        }
        return ANCMode.reported(mask: mask)
    }
}
