import XCTest
@testable import VelaCore

final class ConfigurationStoreTests: XCTestCase {
    func testDefaultConfigurationIsValid() throws {
        XCTAssertNoThrow(try ConfigurationStore().validate(.default))
    }

    func testDuplicateHotkeysAreRejected() {
        let configuration = VelaConfiguration(hotkeys: [
            .init(keys: ["command", "space"], action: .launcher),
            .init(keys: ["space", "command"], action: .clipboard),
        ])
        XCTAssertThrowsError(try ConfigurationStore().validate(configuration))
    }

    func testJavaScriptConfigurationUsesVelaActions() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "vela-test-\(UUID().uuidString).js")
        try """
        Vela.configure({ clipboard: { limit: 12, ignoredBundleIdentifiers: [] } });
        Vela.hotkey("command+q", Vela.showLauncher);
        Vela.command({ id: "site", title: "Site", run: () => Vela.openURL("https://example.com") });
        Vela.snippet({ id: "reply", title: "Reply", group: "Work", value: "Thanks!", keywords: ["thanks"] });
        """.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let configuration = try JavaScriptConfiguration.load(from: file)
        XCTAssertEqual(configuration.clipboard.limit, 12)
        XCTAssertEqual(configuration.hotkeys, [.init(keys: ["command", "q"], action: .launcher)])
        XCTAssertEqual(configuration.commands.first?.action, .openURL("https://example.com"))
        XCTAssertEqual(configuration.snippets, [.init(id: "reply", title: "Reply", value: "Thanks!", group: "Work", keywords: ["thanks"])])
    }
}
