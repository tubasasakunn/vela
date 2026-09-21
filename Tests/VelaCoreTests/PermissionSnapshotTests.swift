import XCTest
@testable import VelaCore

final class PermissionSnapshotTests: XCTestCase {
    func testSummarizesStatesInSetupOrder() {
        let snapshot = PermissionSnapshot(states: [
            .accessibility: true,
            .inputMonitoring: false,
            .screenRecording: true,
            .notifications: false,
        ])

        XCTAssertTrue(snapshot.isGranted(.accessibility))
        XCTAssertFalse(snapshot.isGranted(.inputMonitoring))
        XCTAssertEqual(snapshot.grantedCount, 2)
        XCTAssertEqual(snapshot.nextMissingPermission, .inputMonitoring)
    }
}
