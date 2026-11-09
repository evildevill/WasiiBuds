import XCTest
@testable import BudsDomain

final class DeviceFactsTests: XCTestCase {
    func testVerifiedModelAndTransportAreKeptSeparateFromIOSSupport() {
        XCTAssertEqual(DeviceFacts.productID, "064414")
        XCTAssertTrue(DeviceFacts.transport.contains("GATT"))
        XCTAssertEqual(DeviceFacts.serviceUUIDs.count, 2)
        XCTAssertEqual(DeviceFacts.iOSControlAvailability, .gattCandidate)
    }

    func testConnectionStatesExplainPermissionAndFailure() {
        XCTAssertEqual(LinkPhase.permissionDenied.message, "Bluetooth permission is off")
        XCTAssertEqual(LinkPhase.failed("Connection timed out").message, "Connection timed out")
    }
}
