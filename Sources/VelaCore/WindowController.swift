import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

public struct VelaWindow: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let applicationName: String
    public let bundleIdentifier: String?
    /// A small, current rendering of the window. It is nil until Screen Recording
    /// permission has been granted, or when macOS cannot expose a window's pixels.
    public let preview: NSImage?
    fileprivate let element: AXUIElement?
    fileprivate let processIdentifier: pid_t
    fileprivate let windowID: CGWindowID?
    public static func == (lhs: VelaWindow, rhs: VelaWindow) -> Bool { lhs.id == rhs.id }
}

public final class WindowController {
    private var recentBundleIdentifiers: [String] = []
    private var activationObserver: NSObjectProtocol?
    public init() {
        if let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            recentBundleIdentifiers = [identifier]
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let identifier = application.bundleIdentifier,
                  application.activationPolicy == .regular else { return }
            self?.recentBundleIdentifiers.removeAll(where: { $0 == identifier })
            self?.recentBundleIdentifiers.insert(identifier, at: 0)
        }
    }
    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
    public var accessibilityTrusted: Bool { AXIsProcessTrusted() }
    public var screenRecordingAuthorized: Bool { CGPreflightScreenCaptureAccess() }
    public func requestScreenRecordingPermission() { _ = CGRequestScreenCaptureAccess() }
    public func requestAccessibilityPermission() { AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    public func windows(includeMinimized: Bool = false) async -> [VelaWindow] {
        let recency = Dictionary(uniqueKeysWithValues: recentBundleIdentifiers.enumerated().map { ($0.element, $0.offset) })
        let applications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .sorted {
                let lhs = $0.bundleIdentifier.flatMap { recency[$0] } ?? Int.max
                let rhs = $1.bundleIdentifier.flatMap { recency[$0] } ?? Int.max
                return lhs < rhs
            }
        let applicationsByProcess = Dictionary(uniqueKeysWithValues: applications.map { ($0.processIdentifier, $0) })
        let serverWindows = allWindowServerWindows()
        let shareableContent = try? await SCShareableContent.current
        let accessibilityWindows = applications.flatMap { application in
            windows(for: application, includeMinimized: includeMinimized, serverWindows: serverWindows.filter { $0.processIdentifier == application.processIdentifier })
        }
        var windowsWithPreviews: [VelaWindow] = []
        for window in accessibilityWindows {
            windowsWithPreviews.append(await addingPreview(to: window, from: shareableContent))
        }
        let represented = Set(windowsWithPreviews.compactMap(\.windowID))
        var otherSpaceWindows: [VelaWindow] = []
        for serverWindow in serverWindows {
            guard !represented.contains(serverWindow.id),
                  let application = applicationsByProcess[serverWindow.processIdentifier] else { continue }
            let window = VelaWindow(
                id: "cg-\(serverWindow.id)",
                title: serverWindow.title,
                applicationName: application.localizedName ?? "Application",
                bundleIdentifier: application.bundleIdentifier,
                preview: nil,
                element: nil,
                processIdentifier: serverWindow.processIdentifier,
                windowID: serverWindow.id
            )
            otherSpaceWindows.append(await addingPreview(to: window, from: shareableContent))
        }
        return windowsWithPreviews + otherSpaceWindows
    }
    public func focus(_ window: VelaWindow) {
        NSRunningApplication(processIdentifier: window.processIdentifier)?.activate()
        if let element = window.element { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
    }
    public func moveFocusedWindow(_ action: WindowAction) {
        guard accessibilityTrusted else { return }
        if action == .focusPrevious {
            Task { [weak self] in await self?.focusPrevious() }
            return
        }
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
    private func focusPrevious() async {
        let candidates = await windows()
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
    private func windows(for application: NSRunningApplication, includeMinimized: Bool, serverWindows: [WindowServerWindow]) -> [VelaWindow] {
        let axApp = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let values = value as? [AXUIElement] else { return [] }
        return values.enumerated().compactMap { index, element in
            let title = stringAttribute(element, kAXTitleAttribute) ?? application.localizedName ?? "Untitled"
            let minimized = boolAttribute(element, kAXMinimizedAttribute)
            guard includeMinimized || !minimized else { return nil }
            let windowID = frame(of: element).flatMap { matchingWindow(for: $0, in: serverWindows) }
            return VelaWindow(id: "\(application.processIdentifier)-\(index)-\(title)", title: title, applicationName: application.localizedName ?? "Application", bundleIdentifier: application.bundleIdentifier, preview: nil, element: element, processIdentifier: application.processIdentifier, windowID: windowID)
        }
    }

    private struct WindowServerWindow {
        let id: CGWindowID
        let processIdentifier: pid_t
        let title: String
        let frame: CGRect
    }

    private func allWindowServerWindows() -> [WindowServerWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { window in
            guard let processIdentifier = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber,
                  let title = window[kCGWindowName as String] as? String,
                  !title.isEmpty,
                  let boundsValue = window[kCGWindowBounds as String],
                  let bounds = boundsValue as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 1, frame.height > 1 else { return nil }
            return WindowServerWindow(id: CGWindowID(number.uint32Value), processIdentifier: processIdentifier, title: title, frame: frame)
        }
    }

    private func matchingWindow(for frame: CGRect, in candidates: [WindowServerWindow]) -> CGWindowID? {
        candidates.min { lhs, rhs in
            windowDistance(lhs.frame, from: frame) < windowDistance(rhs.frame, from: frame)
        }?.id
    }

    private func windowDistance(_ candidate: CGRect, from target: CGRect) -> CGFloat {
        abs(candidate.minX - target.minX) + abs(candidate.minY - target.minY)
            + abs(candidate.width - target.width) + abs(candidate.height - target.height)
    }

    private func addingPreview(to window: VelaWindow, from content: SCShareableContent?) async -> VelaWindow {
        guard let windowID = window.windowID,
              let captureWindow = content?.windows.first(where: { $0.windowID == windowID }),
              let image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: captureWindow),
                configuration: SCStreamConfiguration()
              ) else { return window }
        return VelaWindow(
            id: window.id,
            title: window.title,
            applicationName: window.applicationName,
            bundleIdentifier: window.bundleIdentifier,
            preview: thumbnail(from: image),
            element: window.element,
            processIdentifier: window.processIdentifier,
            windowID: window.windowID
        )
    }

    private func thumbnail(from image: CGImage) -> NSImage {
        let source = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let target = CGSize(width: 336, height: 210)
        let thumbnail = NSImage(size: target)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let scale = min(target.width / source.size.width, target.height / source.size.height)
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        source.draw(in: CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2, width: size.width, height: size.height))
        thumbnail.unlockFocus()
        return thumbnail
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
