import BudsDomain
import Foundation

/// Local copies supplement the active profile reported by the earbuds.
/// They are never treated as proof that a profile was applied to the device.
public struct HearingProfileStore {
    private let defaults: UserDefaults
    private let key = "wasiibuds.hearingProfiles"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [HearingProfileRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([HearingProfileRecord].self, from: data) else {
            return []
        }
        return Array(records.filter { $0.values.count == 12 &&
            ($0.scan.isEmpty || $0.scan.count == 168) }.prefix(10))
    }

    public func save(_ records: [HearingProfileRecord]) {
        guard let data = try? JSONEncoder().encode(Array(records.prefix(10))) else { return }
        defaults.set(data, forKey: key)
    }
}
