import AppKit
import CoreGraphics
import VelaCore

final class VelaDelegate: NSObject, NSApplicationDelegate {
    private let configurationStore = ConfigurationStore()
    private let clipboard = ClipboardHistory()
    private let windows = WindowController()
    private let hotkeys = HotkeyManager()
    private let permissions = PermissionCenter()
    private var configuration = VelaConfiguration.default
    private var overlay: OverlayController?
    private var statusItem: NSStatusItem?
    private var modifiedDate: Date?
    private var watcher: Timer?
    private var permissionWatcher: Timer?
    private var contextualPasteTask: Task<Void, Never>?
    private lazy var installer = ApplicationInstaller()
    private lazy var onboarding = OnboardingController()
    private lazy var menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "VelaMenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if installer.installIfNeeded() { return }
        buildMenu()
        overlay = OverlayController(clipboard: clipboard, windowController: windows)
        hotkeys.onAction = { [weak self] action in DispatchQueue.main.async { self?.execute(action) } }
        let shouldShowSetup = VelaLaunchIntent.shouldShowSetup(arguments: CommandLine.arguments)
        if FileManager.default.fileExists(atPath: VelaPaths.configuration.path) {
            reloadConfiguration(showError: true)
            if shouldShowSetup {
                DispatchQueue.main.async { [weak self] in self?.onboarding.showInstallationComplete() }
            }
        } else if shouldShowSetup {
            DispatchQueue.main.async { [weak self] in self?.onboarding.showInstallationComplete() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.onboarding.showWelcome() }
        }
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.reload, object: nil, queue: .main) { [weak self] _ in self?.reloadConfiguration(showError: true) }
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.requestPermission, object: nil, queue: .main) { [weak self] notification in
            guard let request = notification.userInfo?["permission"] as? String else { return }
            self?.requestPermission(named: request)
        }
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.refreshPermissions, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPermissionStatus()
        }
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.showOverlay, object: nil, queue: .main) { [weak self] notification in
            guard let mode = notification.userInfo?["mode"] as? String else { return }
            switch mode {
            case "search": self?.showLauncher()
            case "clipboard": self?.showClipboard()
            case "windows": self?.showSwitcher()
            case "context": self?.pasteContextSnippet()
            default: break
            }
        }
        watcher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reloadWhenChanged() }
        refreshPermissionStatus()
        permissionWatcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissionStatus() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboard.stop()
        permissionWatcher?.invalidate()
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = menuBarIcon
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Vela", action: #selector(showLauncher), keyEquivalent: "")
        menu.addItem(withTitle: "Clipboard", action: #selector(showClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Window switcher", action: #selector(showSwitcher), keyEquivalent: "")
        menu.addItem(withTitle: "Smart paste", action: #selector(pasteContextSnippet), keyEquivalent: "")
        menu.addItem(withTitle: "Capture text from screenshot", action: #selector(captureTextFromScreen), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Set up with AI…", action: #selector(showOnboarding), keyEquivalent: "")
        menu.addItem(withTitle: "Reload configuration", action: #selector(reloadFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Open configuration", action: #selector(openConfiguration), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Vela", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    @objc private func showLauncher() { overlay?.show(.launcher, configuration: configuration) }
    @objc private func showClipboard() { overlay?.show(.clipboard, configuration: configuration) }
    @objc private func showSwitcher() { overlay?.show(.switcher, configuration: configuration) }
    @objc private func pasteContextSnippet() {
        contextualPasteTask?.cancel()
        guard case let .success(context) = FocusedInputInspector.inspect(),
              let targetApplication = NSWorkspace.shared.frontmostApplication,
              !configuration.contextSnippets.isEmpty else { return }
        let candidates = configuration.contextSnippets
        contextualPasteTask = Task { @MainActor [weak self] in
            let ranked = await ContextSnippetRanker.rank(candidates, for: context)
            guard let self,
                  !Task.isCancelled,
                  let content = ranked.first?.content,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApplication.processIdentifier else { return }
            TextPaster.paste(content, using: clipboard, into: targetApplication)
        }
    }
    @objc private func captureTextFromScreen() { execute(.captureTextFromScreen) }
    @objc private func reloadFromMenu() { reloadConfiguration(showError: true) }
    @objc private func openConfiguration() { NSWorkspace.shared.open(VelaPaths.configDirectory) }
    @objc private func showOnboarding() {
        if FileManager.default.fileExists(atPath: VelaPaths.configuration.path) {
            onboarding.showAIChoice()
        } else {
            onboarding.showWelcome()
        }
    }

    private func refreshPermissionStatus() {
        permissions.refresh { states in PermissionStatusStore.write(states) }
    }

    private func requestPermission(named name: String) {
        if let permission = VelaPermission(cliName: name) {
            request(permission)
            return
        }
        guard name == "all" else { return }
        permissions.refresh { [weak self] states in
            guard let permission = VelaPermission.allCases.first(where: { states[$0] != true }) else { return }
            DispatchQueue.main.async { self?.request(permission) }
        }
    }

    private func request(_ permission: VelaPermission) {
        permissions.request(permission)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshPermissionStatus() }
    }

    private func reloadWhenChanged() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: VelaPaths.configuration.path)
        let date = attributes?[.modificationDate] as? Date
        guard date != modifiedDate else { return }
        modifiedDate = date
        reloadConfiguration(showError: false)
    }

    private func reloadConfiguration(showError: Bool) {
        do {
            configuration = try configurationStore.load()
            clipboard.start(configuration: configuration.clipboard)
            hotkeys.register(configuration.hotkeys)
            modifiedDate = (try? FileManager.default.attributesOfItem(atPath: VelaPaths.configuration.path)[.modificationDate]) as? Date
        } catch {
            if showError { presentError(error) }
        }
    }

    private func execute(_ action: VelaAction) {
        switch action {
        case .launcher: showLauncher()
        case .clipboard: showClipboard()
        case .switcher: showSwitcher()
        case .contextSnippets: pasteContextSnippet()
        case .captureTextFromScreen: captureText()
        case let .window(direction): windows.moveFocusedWindow(direction)
        case .quitFrontmostApplication: windows.quitFrontmostApplication()
        case let .command(id):
            guard let command = configuration.commands.first(where: { $0.id == id }) else { return }
            do { try CommandExecutor.run(command) } catch { presentError(error) }
        }
    }

    private func captureText() {
        guard windows.screenRecordingAuthorized else {
            windows.requestScreenRecordingPermission()
            showCaptureStatus(success: false, message: "画面収録を許可してから、もう一度実行してください。")
            return
        }
        ScreenTextCapture.captureInteractively { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .success(text):
                    self?.clipboard.copyText(text)
                    self?.showCaptureStatus(success: true, message: "認識した文字列をクリップボードにコピーしました。")
                case let .failure(error):
                    self?.showCaptureStatus(success: false, message: error.localizedDescription)
                }
            }
        }
    }

    private func showCaptureStatus(success: Bool, message: String) {
        statusItem?.button?.image = NSImage(systemSymbolName: success ? "checkmark" : "exclamationmark.triangle", accessibilityDescription: "Vela")
        statusItem?.button?.toolTip = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.statusItem?.button?.image = self?.menuBarIcon
            self?.statusItem?.button?.toolTip = nil
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Vela could not load its configuration"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Open configuration")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { openConfiguration() }
    }
}
