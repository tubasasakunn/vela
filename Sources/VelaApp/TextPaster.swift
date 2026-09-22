import AppKit
import CoreGraphics
import VelaCore

enum TextPaster {
    static func paste(
        _ value: String,
        using clipboard: ClipboardHistory,
        into application: NSRunningApplication?,
        delay: TimeInterval = 0
    ) {
        guard let application, application != NSRunningApplication.current else {
            clipboard.copyText(value)
            return
        }
        application.activate()
        let targetProcessIdentifier = application.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetProcessIdentifier else { return }
            clipboard.copyText(value)
            postPasteKeystroke()
        }
    }

    private static func postPasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
