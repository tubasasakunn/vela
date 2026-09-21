import AppKit
import CoreGraphics
import SwiftUI
import VelaCore

@main
struct VelaAppMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
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
        case let .window(direction): windows.moveFocusedWindow(direction)
        case .quitFrontmostApplication: windows.quitFrontmostApplication()
        case let .command(id):
            guard let command = configuration.commands.first(where: { $0.id == id }) else { return }
            do { try CommandExecutor.run(command) } catch { presentError(error) }
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

private enum OverlayMode { case launcher, clipboard, switcher }

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
        panel.contentView = NSHostingView(rootView: PaletteView(model: model, select: { [weak self] item in self?.select(item) }, close: { [weak self] in self?.panel.orderOut(nil) }))
        return panel
    }()

    init(clipboard: ClipboardHistory, windowController: WindowController, execute: @escaping (VelaAction) -> Void) {
        self.clipboard = clipboard; self.windowController = windowController; self.executeAction = execute
    }

    func show(_ mode: OverlayMode, configuration: VelaConfiguration) {
        previousApplication = NSWorkspace.shared.frontmostApplication
        switch mode {
        case .launcher: model.configureLauncher(configuration: configuration)
        case .clipboard: model.configureClipboard(entries: clipboard.entries)
        case .switcher: model.configureSwitcher(windows: windowController.windows(includeMinimized: configuration.switcher.includeMinimizedWindows), accessibilityTrusted: windowController.accessibilityTrusted)
        }
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func select(_ item: PaletteItem) {
        panel.orderOut(nil)
        switch item.kind {
        case let .command(command): _ = try? CommandExecutor.run(command)
        case let .application(url): NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case let .clipboard(entry): paste(entry)
        case let .window(window): windowController.focus(window)
        case let .action(action): executeAction(action)
        }
    }

    private func paste(_ entry: ClipboardEntry) {
        clipboard.copy(entry)
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
    @Published var selectedID: UUID?
    func configureLauncher(configuration: VelaConfiguration) {
        title = "Vela"; placeholder = "Search commands and applications"; notice = nil; query = ""
        var next = configuration.commands.map { PaletteItem(command: $0) }
        if configuration.launcher.applicationSearch {
            next += installedApplications()
        }
        items = next
        selectedID = filteredItems.first?.id
    }
    func configureClipboard(entries: [ClipboardEntry]) {
        title = "Clipboard"; placeholder = "Search clipboard history"; notice = nil; query = ""
        items = entries.map(PaletteItem.init(clipboard:))
        selectedID = filteredItems.first?.id
    }
    func configureSwitcher(windows: [VelaWindow], accessibilityTrusted: Bool) {
        title = "Windows"; placeholder = "Search open windows"; query = ""
        notice = accessibilityTrusted ? nil : "Allow Accessibility access in System Settings to list and focus windows."
        items = windows.map(PaletteItem.init(window:))
        selectedID = filteredItems.first?.id
    }
    var filteredItems: [PaletteItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return items }
        return items.filter { $0.searchText.lowercased().localizedCaseInsensitiveContains(term) }
    }

    var selectedItem: PaletteItem? {
        filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
    }

    func selectFirstVisible() { selectedID = filteredItems.first?.id }

    func moveSelection(_ direction: MoveCommandDirection) {
        let visible = filteredItems
        guard !visible.isEmpty else { selectedID = nil; return }
        let current = visible.firstIndex(where: { $0.id == selectedID }) ?? 0
        switch direction {
        case .down: selectedID = visible[min(current + 1, visible.count - 1)].id
        case .up: selectedID = visible[max(current - 1, 0)].id
        default: break
        }
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
}

private struct PaletteItem: Identifiable {
    enum Kind { case command(CommandConfiguration), application(URL), clipboard(ClipboardEntry), window(VelaWindow), action(VelaAction) }
    let id = UUID(); let title: String; let subtitle: String?; let symbol: String; let kind: Kind
    var searchText: String { title + " " + (subtitle ?? "") }
    init(command: CommandConfiguration) { title = command.title; subtitle = command.subtitle; symbol = "terminal"; kind = .command(command) }
    init(application: String, url: URL, detail: String?) { title = application; subtitle = detail; symbol = "app"; kind = .application(url) }
    init(clipboard: ClipboardEntry) {
        title = clipboard.value.replacingOccurrences(of: "\n", with: " ")
        let sourceName = clipboard.sourceBundleIdentifier
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
        let relative = RelativeDateTimeFormatter().localizedString(for: clipboard.createdAt, relativeTo: .now)
        subtitle = [sourceName, relative].compactMap { $0 }.joined(separator: " · ")
        symbol = "doc.on.clipboard"
        kind = .clipboard(clipboard)
    }
    init(window: VelaWindow) { title = window.title; subtitle = window.applicationName; symbol = "macwindow"; kind = .window(window) }
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
        .frame(width: 680, height: 448)
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredItems) { item in
                            Button { select(item) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.symbol).frame(width: 20).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title).lineLimit(1)
                                        if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 50)
                                .contentShape(Rectangle())
                                .background(model.selectedID == item.id ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }
}
