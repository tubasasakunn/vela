import AppKit
import ApplicationServices
import Foundation

public struct VelaWindow: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let applicationName: String
    public let bundleIdentifier: String?
    fileprivate let element: AXUIElement
    public static func == (lhs: VelaWindow, rhs: VelaWindow) -> Bool { lhs.id == rhs.id }
}

public final class WindowController {
    public init() {}
    public var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    public func requestAccessibilityPermission() { AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    public func windows(includeMinimized: Bool = false) -> [VelaWindow] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .flatMap { application in windows(for: application, includeMinimized: includeMinimized) }
    }
    public func focus(_ window: VelaWindow) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == window.bundleIdentifier }) {
            running.activate()
        }
    }
    public func moveFocusedWindow(_ action: WindowAction) {
        guard accessibilityTrusted else { return }
        if action == .focusPrevious { focusPrevious(); return }
        let system = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success, let appValue else { return }
        let app = unsafeBitCast(appValue, to: AXUIElement.self)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success, let windowValue else { return }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        guard let currentFrame = frame(of: window), let currentScreen = screen(containing: currentFrame) else { return }
        let frame = currentScreen.visibleFrame
        let target: CGRect
        switch action {
        case .leftHalf: target = CGRect(x: frame.minX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .rightHalf: target = CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        case .toggleMaximize:
            target = isEffectivelyMaximized(currentFrame, in: frame)
                ? CGRect(x: frame.midX - frame.width / 4, y: frame.midY - frame.height / 4, width: frame.width / 2, height: frame.height / 2)
                : frame
        case .nextDisplay, .previousDisplay:
            guard let destination = adjacentScreen(from: currentScreen, direction: action) else { return }
            target = movedFrame(currentFrame, from: frame, to: destination.visibleFrame)
        case .minimize:
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            return
        case .close:
            var closeButton: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
               let closeButton {
                AXUIElementPerformAction(unsafeBitCast(closeButton, to: AXUIElement.self), kAXPressAction as CFString)
            }
            return
        case .focusPrevious: return
        }
        var position = CGPoint(x: target.minX, y: target.minY)
        var size = CGSize(width: target.width, height: target.height)
        if let positionValue = AXValueCreate(.cgPoint, &position) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) }
        if let sizeValue = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) }
    }
    private func focusPrevious() {
        let candidates = windows()
        guard candidates.count > 1 else { return }
        focus(candidates[1])
    }
    public func quitFrontmostApplication() { NSWorkspace.shared.frontmostApplication?.terminate() }
    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?; var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        let positionAX = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAX = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position), AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
    private func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.max(by: { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        })
    }
    private func adjacentScreen(from screen: NSScreen, direction: WindowAction) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = screens.firstIndex(of: screen), screens.count > 1 else { return nil }
        let offset = direction == .nextDisplay ? 1 : -1
        return screens[(index + offset + screens.count) % screens.count]
    }
    private func movedFrame(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        let relativeX = (frame.minX - source.minX) / source.width
        let relativeY = (frame.minY - source.minY) / source.height
        return CGRect(x: destination.minX + relativeX * destination.width, y: destination.minY + relativeY * destination.height, width: min(frame.width, destination.width), height: min(frame.height, destination.height))
    }
    private func isEffectivelyMaximized(_ frame: CGRect, in visibleFrame: CGRect) -> Bool {
        abs(frame.width - visibleFrame.width) < 4 && abs(frame.height - visibleFrame.height) < 4
    }
    private func windows(for application: NSRunningApplication, includeMinimized: Bool) -> [VelaWindow] {
        let axApp = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let values = value as? [AXUIElement] else { return [] }
        return values.enumerated().compactMap { index, element in
            let title = stringAttribute(element, kAXTitleAttribute) ?? application.localizedName ?? "Untitled"
            let minimized = boolAttribute(element, kAXMinimizedAttribute)
            guard includeMinimized || !minimized else { return nil }
            return VelaWindow(id: "\(application.processIdentifier)-\(index)-\(title)", title: title, applicationName: application.localizedName ?? "Application", bundleIdentifier: application.bundleIdentifier, element: element)
        }
    }
    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }
}

private extension CGRect { var area: CGFloat { max(0, width) * max(0, height) } }
