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
        clipboard.copyText(value)
        guard let application, application != NSRunningApplication.current else { return }
        application.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: postPasteKeystroke)
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
