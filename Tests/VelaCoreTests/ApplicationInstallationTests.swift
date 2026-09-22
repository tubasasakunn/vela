import XCTest
@testable import VelaCore

final class ApplicationInstallationTests: XCTestCase {
    private let applicationDirectories = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
    ]

    func testOffersMoveOnlyFromReadOnlyVolumeOutsideApplications() {
        let diskImageApp = URL(fileURLWithPath: "/Volumes/Vela Installer/Vela.app", isDirectory: true)
        XCTAssertTrue(ApplicationInstallationPolicy.shouldOfferMove(
            bundleURL: diskImageApp,
            isOnReadOnlyVolume: true,
            applicationDirectories: applicationDirectories
        ))
        XCTAssertFalse(ApplicationInstallationPolicy.shouldOfferMove(
            bundleURL: diskImageApp,
            isOnReadOnlyVolume: false,
            applicationDirectories: applicationDirectories
        ))
    }

    func testDoesNotOfferMoveForInstalledApplication() {
        let installedApp = URL(fileURLWithPath: "/Applications/Vela.app", isDirectory: true)
        XCTAssertFalse(ApplicationInstallationPolicy.shouldOfferMove(
            bundleURL: installedApp,
            isOnReadOnlyVolume: true,
            applicationDirectories: applicationDirectories
        ))
    }

    func testApplicationsNamedFolderOnDiskImageIsNotTreatedAsInstalled() {
        let diskImageApp = URL(fileURLWithPath: "/Volumes/Vela/Applications/Vela.app", isDirectory: true)
        XCTAssertFalse(ApplicationInstallationPolicy.isInstalled(
            bundleURL: diskImageApp,
            applicationDirectories: applicationDirectories
        ))
    }

    func testSetupLaunchIntent() {
        XCTAssertTrue(VelaLaunchIntent.shouldShowSetup(arguments: ["Vela", VelaLaunchIntent.showSetupArgument]))
        XCTAssertFalse(VelaLaunchIntent.shouldShowSetup(arguments: ["Vela"]))
    }
}
