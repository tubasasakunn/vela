import AppKit
import VelaCore

final class OnboardingController {
    func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "Vela をあなた向けに整えます"
        alert.informativeText = "まずAIを開きます。AIが `vela init` で設定ファイルと案内スキルを作り、それを読んでからショートカットや定型文を一緒に決めます。"
        alert.addButton(withTitle: "AIと設定する")
        alert.addButton(withTitle: "導入手順を見る")
        alert.addButton(withTitle: "あとで")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            showAIChoice()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(AISetupGuide.url)
        default:
            break
        }
    }

    func showAIChoice() {
        let alert = NSAlert()
        alert.messageText = "設定を相談するAIを選んでください"
        alert.informativeText = "AIには導入手順と、最初に `vela init` を実行する依頼を渡します。初期化後に作られる AGENT.md とスキルをAIが読んでから設定を進めます。"
        alert.addButton(withTitle: "ChatGPT / Codex")
        alert.addButton(withTitle: "Claude")
        alert.addButton(withTitle: "Gemini")
        alert.addButton(withTitle: "あとで")

        let target: AISetupTarget?
        switch alert.runModal() {
        case .alertFirstButtonReturn: target = .chatGPT
        case .alertSecondButtonReturn: target = .claude
        case .alertThirdButtonReturn: target = .gemini
        default: target = nil
        }
        guard let target else { return }
        openConversation(for: target)
    }

    private var bundledCLIPath: String {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/vela").path
    }

    private func openConversation(for target: AISetupTarget) {
        let existingDirectory = FileManager.default.fileExists(atPath: VelaPaths.configuration.path) ? VelaPaths.configDirectory : nil
        let prompt = AISetupGuide.prompt(helperPath: bundledCLIPath, configurationDirectory: existingDirectory)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        if target != .gemini,
           let url = AISetupGuide.conversationURL(for: target, helperPath: bundledCLIPath, configurationDirectory: existingDirectory),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
            return
        }

        if target == .chatGPT,
           let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            NSWorkspace.shared.openApplication(at: application, configuration: .init())
        } else if target == .gemini,
                  let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS") {
            NSWorkspace.shared.openApplication(at: application, configuration: .init())
        }

        let alert = NSAlert()
        alert.messageText = "依頼文をコピーしました"
        alert.informativeText = "AIアプリの新しい会話で Command-V を押すと、Velaの導入手順と相談内容を貼り付けられます。"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
