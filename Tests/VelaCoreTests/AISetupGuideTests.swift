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
        XCTAssertEqual(AISetupGuide.url.absoluteString, "https://vela.basaapp.com/setup.md")
        XCTAssertTrue(prompt.contains("https://vela.basaapp.com/setup.md"))
        XCTAssertTrue(prompt.contains("AGENT.md"))
        XCTAssertTrue(prompt.contains("vela-configuration/SKILL.md"))
        XCTAssertTrue(prompt.contains("init --directory"))
        XCTAssertTrue(prompt.contains("まだありません"))
    }

    func testInstalledTargetIsRecommendedAndShownFirst() {
        let options = AISetupRecommendation.options(installedTargets: [.claude])

        XCTAssertEqual(options.map(\.target), [.claude, .chatGPT, .gemini])
        XCTAssertEqual(options.filter(\.isRecommended).map(\.target), [.claude])
        XCTAssertTrue(options[0].isInstalled)
    }

    func testFirstInstalledTargetInStablePriorityOrderIsRecommended() {
        let options = AISetupRecommendation.options(installedTargets: [.gemini, .chatGPT])

        XCTAssertEqual(options.map(\.target), [.chatGPT, .gemini, .claude])
        XCTAssertEqual(options.filter(\.isRecommended).map(\.target), [.chatGPT])
        XCTAssertTrue(options[1].isInstalled)
    }

    func testNoTargetIsRecommendedWhenNoSupportedAIIsInstalled() {
        let options = AISetupRecommendation.options(installedTargets: [])

        XCTAssertEqual(options.map(\.target), [.chatGPT, .claude, .gemini])
        XCTAssertTrue(options.allSatisfy { !$0.isInstalled && !$0.isRecommended })
    }
}
