import AppKit
import CoreGraphics
import SwiftUI
import VelaCore

@main
struct VelaAppMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let currentProcess = NSRunningApplication.current.processIdentifier
        let previousInstances = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.vela.app")
            .filter { $0.processIdentifier != currentProcess }
        previousInstances.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(1)
        while previousInstances.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
        let delegate = VelaDelegate()
        application.delegate = delegate
        application.run()
    }
}

private final class VelaDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        overlay = OverlayController(clipboard: clipboard, windowController: windows, execute: execute)
        hotkeys.onAction = { [weak self] action in DispatchQueue.main.async { self?.execute(action) } }
        reloadConfiguration(showError: true)
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.reload, object: nil, queue: .main) { [weak self] _ in self?.reloadConfiguration(showError: true) }
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.requestPermission, object: nil, queue: .main) { [weak self] notification in
            guard let request = notification.userInfo?["permission"] as? String else { return }
            self?.requestPermission(named: request)
        }
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.openPermissionSettings, object: nil, queue: .main) { [weak self] notification in
            guard let name = notification.userInfo?["permission"] as? String,
                  let permission = VelaPermission(cliName: name) else { return }
            self?.permissions.openPrivacySettings(for: permission)
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
            case "context": self?.showContextSnippets()
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
        statusItem?.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Vela")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Vela", action: #selector(showLauncher), keyEquivalent: "")
        menu.addItem(withTitle: "Clipboard", action: #selector(showClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "Window switcher", action: #selector(showSwitcher), keyEquivalent: "")
        menu.addItem(withTitle: "Smart paste", action: #selector(pasteContextSnippet), keyEquivalent: "")
        menu.addItem(withTitle: "Capture text from screenshot", action: #selector(captureTextFromScreen), keyEquivalent: "")
        menu.addItem(.separator())
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
    @objc private func showContextSnippets() { pasteContextSnippet() }
    @objc private func pasteContextSnippet() {
        contextualPasteTask?.cancel()
        guard case let .success(context) = FocusedInputInspector.inspect(),
              let targetApplication = NSWorkspace.shared.frontmostApplication,
              !configuration.contextSnippets.isEmpty else { return }
        let candidates = configuration.contextSnippets
        contextualPasteTask = Task { @MainActor [weak self] in
            let ranked = await ContextSnippetRanker.rank(candidates, for: context)
            guard !Task.isCancelled,
                  let content = ranked.first?.content,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApplication.processIdentifier else { return }
            self?.clipboard.copyText(content)
            Self.postPasteKeystroke()
        }
    }
    @objc private func captureTextFromScreen() { execute(.captureTextFromScreen) }
    @objc private func reloadFromMenu() { reloadConfiguration(showError: true) }
    @objc private func openConfiguration() { NSWorkspace.shared.open(VelaPaths.configDirectory) }

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
            self?.statusItem?.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Vela")
            self?.statusItem?.button?.toolTip = nil
        }
    }

    private static func postPasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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

private enum OverlayMode: Equatable { case launcher, clipboard, switcher, contextSnippets }

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OverlayController {
    private let clipboard: ClipboardHistory
    private let windowController: WindowController
    private let executeAction: (VelaAction) -> Void
    private let model = PaletteModel()
    private var previousApplication: NSRunningApplication?
    private var activeMode: OverlayMode?
    private var keyMonitor: Any?
    private var switcherModifier: NSEvent.ModifierFlags?
    private var rankingTask: Task<Void, Never>?
    private lazy var panel: NSPanel = {
        let panel = KeyPanel(contentRect: .init(x: 0, y: 0, width: 680, height: 448), styleMask: [.titled, .fullSizeContentView, .utilityWindow], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: PaletteView(model: model, select: { [weak self] item in self?.select(item) }, close: { [weak self] in self?.hide() }))
        return panel
    }()

    init(clipboard: ClipboardHistory, windowController: WindowController, execute: @escaping (VelaAction) -> Void) {
        self.clipboard = clipboard; self.windowController = windowController; self.executeAction = execute
    }

    func show(_ mode: OverlayMode, configuration: VelaConfiguration) {
        if mode == .switcher, activeMode == .switcher, panel.isVisible {
            model.moveSelection(.down)
            return
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        rankingTask?.cancel()
        activeMode = mode
        switch mode {
        case .launcher: model.configureLauncher(configuration: configuration)
        case .clipboard: model.configureClipboard(entries: clipboard.entries, snippets: configuration.snippets)
        case .switcher:
            if !windowController.accessibilityTrusted { windowController.requestAccessibilityPermission() }
            if !windowController.screenRecordingAuthorized { windowController.requestScreenRecordingPermission() }
            model.configureSwitcher(
                windows: windowController.windows(includeMinimized: configuration.switcher.includeMinimizedWindows),
                accessibilityTrusted: windowController.accessibilityTrusted,
                screenRecordingAuthorized: windowController.screenRecordingAuthorized
            )
        case .contextSnippets:
            let context = FocusedInputInspector.inspect()
            model.configureContextSnippets(configuration.contextSnippets, context: context)
            if case let .success(focusedContext) = context, !configuration.contextSnippets.isEmpty {
                rankingTask = Task { @MainActor [weak self] in
                    let ranked = await ContextSnippetRanker.rank(configuration.contextSnippets, for: focusedContext)
                    guard !Task.isCancelled else { return }
                    self?.model.applyContextRanking(ranked)
                }
            }
        }
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        if mode == .switcher {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            switcherModifier = flags.contains(.maskAlternate) ? .option : (flags.contains(.maskControl) ? .control : nil)
        } else {
            switcherModifier = nil
        }
    }

    private func select(_ item: PaletteItem) {
        if case let .snippetFolder(group) = item.kind {
            model.openFixedText(group: group)
            return
        }
        hide()
        switch item.kind {
        case let .command(command): _ = try? CommandExecutor.run(command)
        case let .application(url): NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case let .settings(url): NSWorkspace.shared.open(url)
        case let .clipboard(entry): paste(entry.value)
        case let .snippet(snippet): paste(snippet.value)
        case let .contextSnippet(snippet): paste(snippet.content)
        case .snippetFolder: break
        case let .window(window): windowController.focus(window)
        case let .action(action): executeAction(action)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .flagsChanged,
               self.activeMode == .switcher,
               let modifier = self.switcherModifier,
               !event.modifierFlags.contains(modifier) {
                if let item = self.model.selectedItem { self.select(item) }
                return nil
            }
            guard event.type == .keyDown else { return event }
            switch event.keyCode {
            case 123:
                if self.activeMode != .switcher, self.model.navigateBack() { return nil }
                self.model.moveSelection(.left); return nil
            case 124:
                if self.activeMode != .switcher,
                   case let .snippetFolder(group)? = self.model.selectedItem?.kind {
                    self.model.openFixedText(group: group)
                    return nil
                }
                self.model.moveSelection(.right); return nil
            case 125: self.model.moveSelection(.down); return nil
            case 126: self.model.moveSelection(.up); return nil
            case 36, 76:
                if let item = self.model.selectedItem { self.select(item) }
                return nil
            case 53:
                if self.model.navigateBack() { return nil }
                self.hide(); return nil
            default: return event
            }
        }
    }

    private func hide() {
        panel.orderOut(nil)
        rankingTask?.cancel()
        rankingTask = nil
        activeMode = nil
        switcherModifier = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    private func paste(_ value: String) {
        clipboard.copyText(value)
        guard let application = previousApplication, application != NSRunningApplication.current else { return }
        application.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let keyCode = CGKeyCode(9) // V
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}

private final class PaletteModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var title = "Vela"
    @Published private(set) var placeholder = "Search commands and applications"
    @Published private(set) var items: [PaletteItem] = []
    @Published private(set) var notice: String?
    @Published private(set) var isWindowSwitcher = false
    @Published var selectedID: UUID?
    private var clipboardHistoryItems: [PaletteItem] = []
    private var fixedTextItems: [PaletteItem] = []
    private var fixedTextFolder: PaletteItem?
    private var fixedTextPath: String?
    func configureLauncher(configuration: VelaConfiguration) {
        title = "Vela"; placeholder = "Search commands and applications"; notice = nil; query = ""
        isWindowSwitcher = false
        clipboardHistoryItems = []; fixedTextItems = []; fixedTextFolder = nil; fixedTextPath = nil
        var next = configuration.commands.map { PaletteItem(command: $0) }
        if configuration.launcher.applicationSearch {
            next += settingsItems()
            next += installedApplications()
        }
        items = next
        selectedID = filteredItems.first?.id
    }
    func configureClipboard(entries: [ClipboardEntry], snippets: [SnippetConfiguration]) {
        title = "Clipboard"; placeholder = "Search clipboard history"; notice = nil; query = ""
        isWindowSwitcher = false
        clipboardHistoryItems = entries.map(PaletteItem.init(clipboard:))
        fixedTextItems = snippets.map(PaletteItem.init(snippet:))
        fixedTextFolder = snippets.isEmpty ? nil : PaletteItem(snippetFolderCount: snippets.count)
        fixedTextPath = nil
        items = clipboardHistoryItems + (fixedTextFolder.map { [$0] } ?? [])
        selectedID = filteredItems.first?.id
    }
    func configureSwitcher(windows: [VelaWindow], accessibilityTrusted: Bool, screenRecordingAuthorized: Bool) {
        title = "Windows"; placeholder = "Search open windows"; query = ""
        isWindowSwitcher = true
        clipboardHistoryItems = []; fixedTextItems = []; fixedTextFolder = nil; fixedTextPath = nil
        notice = !accessibilityTrusted
            ? "個別のウィンドウとその画面を表示するには「アクセシビリティ」の許可が必要です。システム設定でVelaを許可してから、もう一度Option + Tabを押してください。"
            : !screenRecordingAuthorized
                ? "画面プレビューには「画面収録」の許可が必要です。システム設定でVelaを許可してから、もう一度Option + Tabを押してください。"
                : nil
        if accessibilityTrusted {
            items = windows.map(PaletteItem.init(window:))
        } else {
            items = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !$0.isTerminated }
                .compactMap { application in
                    guard let url = application.bundleURL, let name = application.localizedName else { return nil }
                    return PaletteItem(application: name, url: url, detail: application.bundleIdentifier)
                }
        }
        selectedID = (filteredItems.dropFirst().first ?? filteredItems.first)?.id
    }
    func configureContextSnippets(_ snippets: [ContextSnippetConfiguration], context: Result<FocusedInputContext, FocusedInputError>) {
        title = "Smart paste"; placeholder = "Search contextual text"; query = ""
        isWindowSwitcher = false
        clipboardHistoryItems = []; fixedTextItems = []; fixedTextFolder = nil; fixedTextPath = nil
        items = snippets.map(PaletteItem.init(contextSnippet:))
        switch context {
        case let .success(value): notice = "Choosing for \(value.label)…"
        case let .failure(error): notice = error.localizedDescription
        }
        selectedID = filteredItems.first?.id
    }
    func applyContextRanking(_ snippets: [ContextSnippetConfiguration]) {
        guard title == "Smart paste" else { return }
        items = snippets.map(PaletteItem.init(contextSnippet:))
        notice = "On-device suggestion ready. Press Return to paste."
        selectedID = filteredItems.first?.id
    }
    var filteredItems: [PaletteItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            let searchable = fixedTextFolder == nil ? items : clipboardHistoryItems + fixedTextItems
            return searchable.filter { $0.searchText.lowercased().localizedCaseInsensitiveContains(term) }
        }
        return items
    }

    var selectedItem: PaletteItem? {
        filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
    }

    func selectFirstVisible() { selectedID = filteredItems.first?.id }

    func moveSelection(_ direction: MoveCommandDirection) {
        let visible = filteredItems
        guard !visible.isEmpty else { selectedID = nil; return }
        let current = visible.firstIndex(where: { $0.id == selectedID }) ?? 0
        let step = isWindowSwitcher ? 4 : 1
        switch direction {
        case .right: selectedID = visible[min(current + 1, visible.count - 1)].id
        case .left: selectedID = visible[max(current - 1, 0)].id
        case .down: selectedID = visible[min(current + step, visible.count - 1)].id
        case .up: selectedID = visible[max(current - step, 0)].id
        default: break
        }
    }

    func openFixedText(group: String?) {
        guard fixedTextFolder != nil else { return }
        query = ""
        fixedTextPath = group ?? ""
        title = group ?? "Fixed text"
        placeholder = "Search fixed text"
        if let group {
            items = fixedTextItems.filter { $0.snippetGroup == group }
        } else {
            let ungrouped = fixedTextItems.filter { $0.snippetGroup == nil }
            let groups = Array(Set(fixedTextItems.compactMap(\.snippetGroup))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            // A single imported Clipy folder should not add an otherwise empty
            // navigation step. Multiple folders remain available for browsing.
            if ungrouped.isEmpty, groups.count == 1 {
                openFixedText(group: groups[0])
                return
            }
            items = ungrouped + groups.map(PaletteItem.init(snippetGroup:))
        }
        selectedID = items.first?.id
    }

    @discardableResult
    func navigateBack() -> Bool {
        guard fixedTextPath != nil else { return false }
        query = ""
        let groups = Set(fixedTextItems.compactMap(\.snippetGroup))
        let bypassesRoot = fixedTextItems.allSatisfy { $0.snippetGroup != nil } && groups.count == 1
        if fixedTextPath != "", !bypassesRoot {
            openFixedText(group: nil)
        } else {
            fixedTextPath = nil
            title = "Clipboard"
            placeholder = "Search clipboard history"
            items = clipboardHistoryItems + (fixedTextFolder.map { [$0] } ?? [])
            selectedID = fixedTextFolder?.id ?? items.first?.id
        }
        return true
    }

    private func installedApplications() -> [PaletteItem] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        ]
        var applications: [String: PaletteItem] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let identifier = bundle?.bundleIdentifier
                applications[url.standardizedFileURL.path] = PaletteItem(application: name, url: url, detail: identifier)
            }
        }
        for application in NSWorkspace.shared.runningApplications {
            guard let url = application.bundleURL, let name = application.localizedName else { continue }
            applications[url.standardizedFileURL.path] = PaletteItem(application: name, url: url, detail: application.bundleIdentifier)
        }
        return applications.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func settingsItems() -> [PaletteItem] {
        [
            ("Wi-Fi", "wifi", "x-apple.systempreferences:com.apple.wifi-settings-extension"),
            ("Bluetooth", "bluetooth", "x-apple.systempreferences:com.apple.BluetoothSettings"),
            ("Network", "network", "x-apple.systempreferences:com.apple.Network-Settings.extension"),
            ("Displays", "display", "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
            ("Sound", "speaker.wave.2", "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
            ("Keyboard", "keyboard", "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
            ("Privacy & Security", "hand.raised", "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
        ].compactMap { title, symbol, rawURL in
            URL(string: rawURL).map { PaletteItem(settings: title, url: $0, symbol: symbol) }
        }
    }
}

private struct PaletteItem: Identifiable {
    enum Kind { case command(CommandConfiguration), application(URL), settings(URL), clipboard(ClipboardEntry), snippet(SnippetConfiguration), contextSnippet(ContextSnippetConfiguration), snippetFolder(String?), window(VelaWindow), action(VelaAction) }
    let id = UUID(); let title: String; let subtitle: String?; let symbol: String; let icon: NSImage?; let kind: Kind
    var searchText: String {
        let base = title + " " + (subtitle ?? "")
        switch kind {
        case let .command(command): return base + " " + command.keywords.joined(separator: " ")
        case let .snippet(snippet): return base + " " + snippet.keywords.joined(separator: " ")
        default: return base
        }
    }
    var isSnippetFolder: Bool {
        if case .snippetFolder = kind { return true }
        return false
    }
    var snippetGroup: String? {
        if case let .snippet(snippet) = kind { return snippet.group }
        return nil
    }
    init(command: CommandConfiguration) { title = command.title; subtitle = command.subtitle; symbol = "terminal"; icon = nil; kind = .command(command) }
    init(application: String, url: URL, detail: String?) {
        title = application; subtitle = detail; symbol = "app"; icon = NSWorkspace.shared.icon(forFile: url.path); kind = .application(url)
    }
    init(settings: String, url: URL, symbol: String) {
        title = settings; subtitle = "System Settings"; self.symbol = symbol; icon = nil; kind = .settings(url)
    }
    init(clipboard: ClipboardEntry) {
        title = clipboard.value.replacingOccurrences(of: "\n", with: " ")
        let sourceURL = clipboard.sourceBundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        let sourceName = sourceURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
        let relative = RelativeDateTimeFormatter().localizedString(for: clipboard.createdAt, relativeTo: .now)
        subtitle = [sourceName, relative].compactMap { $0 }.joined(separator: " · ")
        symbol = "doc.on.clipboard"
        icon = sourceURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        kind = .clipboard(clipboard)
    }
    init(snippet: SnippetConfiguration) {
        title = snippet.title
        subtitle = [snippet.group, snippet.value].compactMap { $0 }.joined(separator: " · ")
        symbol = "pin.fill"
        icon = nil
        kind = .snippet(snippet)
    }
    init(contextSnippet snippet: ContextSnippetConfiguration) {
        title = snippet.name
        subtitle = snippet.description
        symbol = "sparkles"
        icon = nil
        kind = .contextSnippet(snippet)
    }
    init(snippetFolderCount count: Int) {
        title = "Fixed text"
        subtitle = "\(count) items · Right arrow to expand"
        symbol = "folder"
        icon = nil
        kind = .snippetFolder(nil)
    }
    init(snippetGroup group: String) {
        title = group
        subtitle = "Fixed text folder · Right arrow to open"
        symbol = "folder"
        icon = nil
        kind = .snippetFolder(group)
    }
    init(window: VelaWindow) {
        title = window.title; subtitle = window.applicationName; symbol = "macwindow"
        icon = window.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.map { NSWorkspace.shared.icon(forFile: $0.path) }
        kind = .window(window)
    }
}

private struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    let select: (PaletteItem) -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    var body: some View {
        surface
            .onAppear { searchFocused = true }
            .onChange(of: model.query) { _, _ in model.selectFirstVisible() }
            .onMoveCommand { model.moveSelection($0) }
            .onExitCommand(perform: close)
    }
    @ViewBuilder private var surface: some View {
        let content = VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle").font(.system(size: 17, weight: .medium)).foregroundStyle(.tint)
                TextField(model.placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .focused($searchFocused)
                    .onSubmit { if let item = model.selectedItem { select(item) } }
                Text(model.title).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).frame(height: 64)
            .background(.thinMaterial, in: Capsule())
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider().opacity(0.45)
            results
        }
        .frame(width: model.isWindowSwitcher ? 880 : 680, height: model.isWindowSwitcher ? 540 : 448)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
    @ViewBuilder private var results: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        } else if model.filteredItems.isEmpty {
            ContentUnavailableView("Nothing found", systemImage: "magnifyingglass", description: Text("Try a different search."))
        } else {
            if model.isWindowSwitcher {
                windowThumbnailGrid
            } else {
                standardList
            }
        }
    }

    @ViewBuilder private var standardList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.filteredItems) { item in
                        Button { select(item) } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if let icon = item.icon { Image(nsImage: icon).resizable().scaledToFit() }
                                    else { Image(systemName: item.symbol).resizable().scaledToFit().padding(5) }
                                }
                                .frame(width: 30, height: 30).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(1)
                                    if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).frame(height: 50).contentShape(Rectangle())
                            .background(model.selectedID == item.id ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain).id(item.id)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 8)
            }
            .onChange(of: model.selectedID) { _, id in if let id { withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } } }
        }
    }

    @ViewBuilder private var windowThumbnailGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 210), spacing: 14)],
                    spacing: 16
                ) {
                    ForEach(model.filteredItems) { item in
                        Button { select(item) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Group {
                                    if case let .window(window) = item.kind, let preview = window.preview {
                                        Image(nsImage: preview).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: item.symbol).resizable().scaledToFit().padding(42).foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 118)
                                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                HStack(spacing: 7) {
                                    Group {
                                        if let icon = item.icon { Image(nsImage: icon).resizable().scaledToFit() }
                                        else { Image(systemName: item.symbol).resizable().scaledToFit().padding(2) }
                                    }
                                    .frame(width: 18, height: 18).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        if let subtitle = item.subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                }
                            }
                            .padding(8)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .background(model.selectedID == item.id ? Color.accentColor.opacity(0.16) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(model.selectedID == item.id ? Color.accentColor.opacity(0.85) : .white.opacity(0.08), lineWidth: model.selectedID == item.id ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain).id(item.id)
                    }
                }.padding(16)
            }
            .onChange(of: model.selectedID) { _, id in if let id { withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } } }
        }
    }
}
