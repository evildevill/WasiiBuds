import Foundation

/// Facts confirmed in WasiiBuds. These are not claims of iOS availability.
public enum DeviceFacts {
    public static let model = "OnePlus Nord Buds 3 Pro"
    public static let productID = "064414"
    public static let transport = "Classic RFCOMM on Android; proprietary GATT also observed for this model"
    public static let iOSControlAvailability: TransportAssessment = .gattCandidate
    public static let serviceUUIDs = [
        "0000079A-D102-11E1-9B23-00025B00A5A5",
        "00001107-D102-11E1-9B23-00025B00A5A5",
    ]

    public static let androidConfirmed: [Capability] = [
        .init(name: "Battery", symbol: "battery.100percent"),
        .init(name: "Noise control", symbol: "waveform"),
        .init(name: "Low latency", symbol: "bolt"),
        .init(name: "Equalizer", symbol: "slider.horizontal.3"),
        .init(name: "Gestures", symbol: "hand.tap"),
        .init(name: "Wear detection", symbol: "ear"),
        .init(name: "Find earbuds", symbol: "location"),
        .init(name: "Dual connection", symbol: "link"),
        .init(name: "Hearing profile", symbol: "waveform.path"),
        .init(name: "High-quality audio", symbol: "music.note"),
    ]
}

public struct Capability: Equatable, Sendable, Identifiable {
    public let name: String
    public let symbol: String
    public var id: String { name }

    public init(name: String, symbol: String) {
        self.name = name
        self.symbol = symbol
    }
}

public enum TransportAssessment: Equatable, Sendable {
    case gattCandidate
}

public enum LinkPhase: Equatable, Sendable {
    case waitingForPermission
    case permissionDenied
    case bluetoothOff
    case ready
    case scanning
    case connecting(UUID)
    case inspecting(UUID)
    case connected(UUID)
    case failed(String)

    public var message: String {
        switch self {
        case .waitingForPermission: "Waiting for Bluetooth permission"
        case .permissionDenied: "Bluetooth permission is off"
        case .bluetoothOff: "Turn on Bluetooth to explore nearby devices"
        case .ready: "Ready to scan nearby Bluetooth devices"
        case .scanning: "Scanning for nearby Bluetooth devices"
        case .connecting: "Connecting to the advertised device"
        case .inspecting: "Reading available service identifiers"
        case .connected: "Bluetooth device connected for inspection"
        case .failed(let reason): reason
        }
    }
}
