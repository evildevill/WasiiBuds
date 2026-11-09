import BudsDomain
import BudsStorage
import Foundation
import XCTest

final class HearingProfileStoreTests: XCTestCase {
    func testRecordsSurviveReloadAndInvalidRecordsAreDiscarded() throws {
        let suite = "WasiiBudsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HearingProfileStore(defaults: defaults)
        let valid = HearingProfileRecord(id: 1, name: "My sound",
                                         values: [Int8](repeating: -25, count: 12))
        let invalid = HearingProfileRecord(id: 2, name: "Incomplete", values: [1])
        store.save([valid, invalid])

        XCTAssertEqual(HearingProfileStore(defaults: defaults).load(), [valid])
    }

    func testStoredRecordCountIsBounded() throws {
        let suite = "WasiiBudsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HearingProfileStore(defaults: defaults)
        let records = (1...12).map { id in
            HearingProfileRecord(id: UInt32(id), name: "Profile \(id)",
                                 values: [Int8](repeating: 0, count: 12))
        }
        store.save(records)

        XCTAssertEqual(store.load().map(\.id), Array(UInt32(1)...UInt32(10)))
    }
}
