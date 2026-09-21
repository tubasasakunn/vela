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
        Vela.hotkey("control+option+space", Vela.showContextSnippets);
        Vela.hotkey("control+option+o", Vela.captureTextFromScreen);
        Vela.command({ id: "site", title: "Site", run: () => Vela.openURL("https://example.com") });
        Vela.snippet({ id: "reply", title: "Reply", group: "Work", value: "Thanks!", keywords: ["thanks"] });
        Vela.configure({ contextSnippets: [{ name: "Office", description: "Office address field", content: "Tokyo" }] });
        """.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let configuration = try JavaScriptConfiguration.load(from: file)
        XCTAssertEqual(configuration.clipboard.limit, 12)
        XCTAssertEqual(configuration.hotkeys, [.init(keys: ["command", "q"], action: .launcher), .init(keys: ["control", "option", "space"], action: .contextSnippets), .init(keys: ["control", "option", "o"], action: .captureTextFromScreen)])
        XCTAssertEqual(configuration.commands.first?.action, .openURL("https://example.com"))
        XCTAssertEqual(configuration.snippets, [.init(id: "reply", title: "Reply", value: "Thanks!", group: "Work", keywords: ["thanks"])])
        XCTAssertEqual(configuration.contextSnippets, [.init(name: "Office", content: "Tokyo", description: "Office address field")])
    }

    func testDuplicateContextSnippetNamesAreRejected() {
        let configuration = VelaConfiguration(contextSnippets: [
            .init(name: "Address", content: "A", description: "First"),
            .init(name: "Address", content: "B", description: "Second"),
        ])
        XCTAssertThrowsError(try ConfigurationStore().validate(configuration))
    }

    func testScreenTextLinesAreReadTopToBottomThenLeftToRight() {
        let lines = [
            RecognizedScreenTextLine(text: "right", bounds: .init(x: 0.58, y: 0.76, width: 0.2, height: 0.04)),
            RecognizedScreenTextLine(text: "second", bounds: .init(x: 0.12, y: 0.55, width: 0.2, height: 0.04)),
            RecognizedScreenTextLine(text: "left", bounds: .init(x: 0.12, y: 0.75, width: 0.2, height: 0.04)),
        ]
        XCTAssertEqual(ScreenTextCapture.arrangedText(lines), "left right\nsecond")
    }
}
