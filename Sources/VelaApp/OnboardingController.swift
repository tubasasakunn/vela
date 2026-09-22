import AppKit
import SwiftUI
import VelaCore

final class OnboardingController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private var entryPage: OnboardingEntryPage?

    func showWelcome() {
        entryPage = .welcome
        show(.welcome)
    }

    func showInstallationComplete() {
        entryPage = .installationComplete
        show(.installationComplete)
    }

    func showAIChoice() {
        entryPage = nil
        showAIChoicePage()
    }

    private func showAIChoicePage() {
        show(.aiChoice(options: AISetupRecommendation.options(installedTargets: installedTargets())))
    }

    private var bundledCLIPath: String {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/vela").path
    }

    private func openConversation(for target: AISetupTarget) {
        let existingDirectory = FileManager.default.fileExists(atPath: VelaPaths.configuration.path) ? VelaPaths.configDirectory : nil
        let prompt = AISetupGuide.prompt(helperPath: bundledCLIPath, configurationDirectory: existingDirectory)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        var openAction: (() -> Void)?
        if target != .gemini,
           let url = AISetupGuide.conversationURL(for: target, helperPath: bundledCLIPath, configurationDirectory: existingDirectory),
           NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            openAction = { NSWorkspace.shared.open(url) }
        } else if target == .chatGPT,
                  let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            openAction = { NSWorkspace.shared.openApplication(at: application, configuration: .init()) }
        } else if target == .gemini,
                  let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.GeminiMacOS") {
            openAction = { NSWorkspace.shared.openApplication(at: application, configuration: .init()) }
        }

        show(.handoff(target: target, openedAutomatically: openAction != nil))
        if let openAction {
            DispatchQueue.main.async(execute: openAction)
        }
    }

    private func show(_ page: OnboardingPage) {
        let windowController = windowController ?? makeWindowController()
        self.windowController = windowController
        let view = OnboardingView(
            page: page,
            chooseAI: { [weak self] target in self?.openConversation(for: target) },
            continueToAIChoice: { [weak self] in self?.showAIChoicePage() },
            backToEntry: { [weak self] in self?.showEntryPage() },
            backToAIChoice: { [weak self] in self?.showAIChoicePage() },
            showGuide: { NSWorkspace.shared.open(AISetupGuide.url) },
            dismiss: { [weak self] in self?.windowController?.close() }
        )
        if let host = windowController.contentViewController as? NSHostingController<OnboardingView> {
            host.rootView = view
        } else {
            windowController.contentViewController = NSHostingController(rootView: view)
        }
        if windowController.window?.isVisible != true {
            if windowController.window?.setFrameUsingName("VelaSetup") != true {
                windowController.window?.center()
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func showEntryPage() {
        switch entryPage {
        case .welcome: show(.welcome)
        case .installationComplete: show(.installationComplete)
        case nil: windowController?.close()
        }
    }

    private func installedTargets() -> Set<AISetupTarget> {
        var targets = Set<AISetupTarget>()
        let bundleIdentifiers: [(AISetupTarget, [String])] = [
            (.chatGPT, ["com.openai.codex", "com.openai.chat"]),
            (.claude, ["com.anthropic.claudefordesktop"]),
            (.gemini, ["com.google.GeminiMacOS"]),
        ]
        for (target, identifiers) in bundleIdentifiers where identifiers.contains(where: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }) {
            targets.insert(target)
        }
        return targets
    }

    private func makeWindowController() -> NSWindowController {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vela"
        window.isMovable = true
        window.setFrameAutosaveName("VelaSetup")
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentMinSize = NSSize(width: 520, height: 400)
        window.delegate = self
        return NSWindowController(window: window)
    }

    func windowWillClose(_ notification: Notification) {
        entryPage = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

private enum OnboardingEntryPage {
    case welcome
    case installationComplete
}
