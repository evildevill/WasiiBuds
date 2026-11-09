import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var mode: String?
    public var batteryUpdatedAt: Date?
    public var connected: Bool

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil,
                mode: String? = nil, batteryUpdatedAt: Date? = nil,
                connected: Bool = false) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.mode = mode
        self.batteryUpdatedAt = batteryUpdatedAt
        self.connected = connected
    }

    /// Keep the last reading while offline, but never show an earlier session's
    /// battery or noise mode as a fresh reading after reconnecting.
    public mutating func update(left: Int?, right: Int?, caseLevel: Int?, mode: String?,
                                connected: Bool, at date: Date) {
        if connected && !self.connected {
            self.left = left
            self.right = right
            self.caseLevel = caseLevel
            self.mode = mode
            batteryUpdatedAt = [left, right, caseLevel].contains { $0 != nil } ? date : nil
        } else if connected {
            let oldLevels = [self.left, self.right, self.caseLevel]
            self.left = left ?? self.left
            self.right = right ?? self.right
            self.caseLevel = caseLevel ?? self.caseLevel
            self.mode = mode ?? self.mode
            if oldLevels != [self.left, self.right, self.caseLevel] {
                batteryUpdatedAt = date
            }
        }
        self.connected = connected
    }
}

public enum WidgetSnapshotStore {
    public static let group = "group.com.wasii.WasiiBuds"
    private static let key = "buds.widget.snapshot.v1"

    public static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: group),
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
