import XCTest
@testable import VelaCore

final class AISetupGuideTests: XCTestCase {
    func testCodexURLCarriesTheSetupPrompt() throws {
        let directory = URL(fileURLWithPath: "/tmp/vela settings", isDirectory: true)
        let helper = "/Applications/Vela.app/Contents/Helpers/vela"
        let url = try XCTUnwrap(AISetupGuide.conversationURL(for: .chatGPT, helperPath: helper, configurationDirectory: directory))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "codex")
        XCTAssertEqual(components.host, "threads")
        XCTAssertEqual(components.path, "/new")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "prompt" })?.value, AISetupGuide.prompt(helperPath: helper, configurationDirectory: directory))
    }

    func testClaudeURLCarriesTheSetupPrompt() throws {
        let directory = URL(fileURLWithPath: "/tmp/vela", isDirectory: true)
        let helper = "/Applications/Vela.app/Contents/Helpers/vela"
        let url = try XCTUnwrap(AISetupGuide.conversationURL(for: .claude, helperPath: helper, configurationDirectory: directory))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "claude")
        XCTAssertEqual(components.host, "claude.ai")
        XCTAssertEqual(components.path, "/new")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, AISetupGuide.prompt(helperPath: helper, configurationDirectory: directory))
    }

    func testPromptRequiresTheLocalAgentInstructions() {
        let prompt = AISetupGuide.prompt(helperPath: "/Applications/Vela.app/Contents/Helpers/vela")
        XCTAssertTrue(prompt.contains("AGENT.md"))
        XCTAssertTrue(prompt.contains("vela-configuration/SKILL.md"))
        XCTAssertTrue(prompt.contains("init --directory"))
        XCTAssertTrue(prompt.contains("まだありません"))
    }
}
