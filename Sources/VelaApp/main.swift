import AppKit
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
    private var configuration = VelaConfiguration.default
    private var overlay: OverlayController?
    private var statusItem: NSStatusItem?
    private var modifiedDate: Date?
    private var watcher: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        overlay = OverlayController(clipboard: clipboard, windowController: windows, execute: execute)
        hotkeys.onAction = { [weak self] action in DispatchQueue.main.async { self?.execute(action) } }
        reloadConfiguration(showError: true)
        DistributedNotificationCenter.default().addObserver(forName: VelaNotifications.reload, object: nil, queue: .main) { [weak self] _ in self?.reloadConfiguration(showError: true) }
        watcher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.reloadWhenChanged() }
    }

    func applicationWillTerminate(_ notification: Notification) { clipboard.stop() }

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
        case let .clipboard(entry): clipboard.copy(entry)
        case let .window(window): windowController.focus(window)
        case let .action(action): executeAction(action)
        }
    }
}

private final class PaletteModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var title = "Vela"
    @Published private(set) var placeholder = "Search commands and applications"
    @Published private(set) var items: [PaletteItem] = []
    @Published private(set) var notice: String?
    func configureLauncher(configuration: VelaConfiguration) {
        title = "Vela"; placeholder = "Search commands and applications"; notice = nil; query = ""
        var next = configuration.commands.map { PaletteItem(command: $0) }
        if configuration.launcher.applicationSearch {
            next += NSWorkspace.shared.runningApplications.compactMap { app in
                guard let url = app.bundleURL, let name = app.localizedName else { return nil }
                return PaletteItem(application: name, url: url, detail: app.bundleIdentifier)
            }
        }
        items = next
    }
    func configureClipboard(entries: [ClipboardEntry]) {
        title = "Clipboard"; placeholder = "Search clipboard history"; notice = nil; query = ""
        items = entries.map(PaletteItem.init(clipboard:))
    }
    func configureSwitcher(windows: [VelaWindow], accessibilityTrusted: Bool) {
        title = "Windows"; placeholder = "Search open windows"; query = ""
        notice = accessibilityTrusted ? nil : "Allow Accessibility access in System Settings to list and focus windows."
        items = windows.map(PaletteItem.init(window:))
    }
    var filteredItems: [PaletteItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return items }
        return items.filter { $0.searchText.lowercased().localizedCaseInsensitiveContains(term) }
    }
}

private struct PaletteItem: Identifiable {
    enum Kind { case command(CommandConfiguration), application(URL), clipboard(ClipboardEntry), window(VelaWindow), action(VelaAction) }
    let id = UUID(); let title: String; let subtitle: String?; let symbol: String; let kind: Kind
    var searchText: String { title + " " + (subtitle ?? "") }
    init(command: CommandConfiguration) { title = command.title; subtitle = command.subtitle; symbol = "terminal"; kind = .command(command) }
    init(application: String, url: URL, detail: String?) { title = application; subtitle = detail; symbol = "app"; kind = .application(url) }
    init(clipboard: ClipboardEntry) { title = clipboard.value.replacingOccurrences(of: "\n", with: " "); subtitle = clipboard.sourceBundleIdentifier; symbol = "doc.on.clipboard"; kind = .clipboard(clipboard) }
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
            .onExitCommand(perform: close)
    }
    @ViewBuilder private var surface: some View {
        let content = VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle").font(.system(size: 17, weight: .medium)).foregroundStyle(.tint)
                TextField(model.placeholder, text: $model.query).textFieldStyle(.plain).font(.system(size: 20, weight: .regular)).focused($searchFocused)
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
            List(model.filteredItems) { item in
                Button { select(item) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol).frame(width: 20).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(1)
                            if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, 4)
            }.listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
}
