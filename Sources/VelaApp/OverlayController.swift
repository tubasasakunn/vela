import AppKit
import CoreGraphics
import SwiftUI
import VelaCore

enum OverlayMode: Equatable { case launcher, clipboard, switcher }

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayController {
    private let clipboard: ClipboardHistory
    private let windowController: WindowController
    private let model = PaletteModel()
    private var previousApplication: NSRunningApplication?
    private var activeMode: OverlayMode?
    private var keyMonitor: Any?
    private var switcherModifier: NSEvent.ModifierFlags?
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

    init(clipboard: ClipboardHistory, windowController: WindowController) {
        self.clipboard = clipboard
        self.windowController = windowController
    }

    func show(_ mode: OverlayMode, configuration: VelaConfiguration) {
        if mode == .switcher, activeMode == .switcher, panel.isVisible {
            model.moveSelection(.down)
            return
        }
        previousApplication = NSWorkspace.shared.frontmostApplication
        activeMode = mode
        switch mode {
        case .launcher: model.configureLauncher(configuration: configuration)
        case .clipboard: model.configureClipboard(entries: clipboard.entries, snippets: configuration.snippets)
        case .switcher:
            if !windowController.accessibilityTrusted { windowController.requestAccessibilityPermission() }
            if !windowController.screenRecordingAuthorized { windowController.requestScreenRecordingPermission() }
            model.configureSwitcher(
                windows: [],
                accessibilityTrusted: windowController.accessibilityTrusted,
                screenRecordingAuthorized: windowController.screenRecordingAuthorized
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                let windows = await self.windowController.windows(includeMinimized: configuration.switcher.includeMinimizedWindows)
                guard self.activeMode == .switcher, self.panel.isVisible else { return }
                self.model.configureSwitcher(
                    windows: windows,
                    accessibilityTrusted: self.windowController.accessibilityTrusted,
                    screenRecordingAuthorized: self.windowController.screenRecordingAuthorized
                )
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
        case .snippetFolder: break
        case let .window(window): windowController.focus(window)
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
        activeMode = nil
        switcherModifier = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    private func paste(_ value: String) {
        TextPaster.paste(value, using: clipboard, into: previousApplication, delay: 0.12)
    }
}
