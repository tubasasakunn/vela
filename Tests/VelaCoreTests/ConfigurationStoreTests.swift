import XCTest
@testable import VelaCore

final class ConfigurationStoreTests: XCTestCase {
    func testDefaultConfigurationIsValid() throws {
        XCTAssertNoThrow(try ConfigurationStore().validate(.default))
    }

    func testWritesDefaultConfigurationToSelectedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vela-config-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appending(path: "vela.js")
        try ConfigurationStore().writeDefault(to: destination)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertNoThrow(try JavaScriptConfiguration.load(from: destination))
    }

    func testWritesConfigurationSkillWithoutOverwritingUserEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "vela-skill-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        try ConfigurationSkill.write(to: directory)
        let agent = directory.appending(path: "AGENT.md")
        let skill = directory.appending(path: ".agent/skills/vela-configuration/SKILL.md")
        let reference = directory.appending(path: ".agent/skills/vela-configuration/references/vela-js-api.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: skill.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reference.path))
        XCTAssertTrue(try String(contentsOf: agent, encoding: .utf8).contains("vela-configuration"))
        XCTAssertTrue(try String(contentsOf: skill, encoding: .utf8).contains("Vela Configuration"))
        XCTAssertTrue(try String(contentsOf: reference, encoding: .utf8).contains("Vela.hotkey"))

        try "user edit".write(to: skill, atomically: true, encoding: .utf8)
        try "user instructions".write(to: agent, atomically: true, encoding: .utf8)
        try ConfigurationSkill.write(to: directory)
        XCTAssertEqual(try String(contentsOf: skill, encoding: .utf8), "user edit")
        XCTAssertEqual(try String(contentsOf: agent, encoding: .utf8), "user instructions")
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
