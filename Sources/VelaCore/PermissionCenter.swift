import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import UserNotifications

public enum VelaPermission: CaseIterable, Hashable, Identifiable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case notifications

    public var id: Self { self }
    public var cliName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "input-monitoring"
        case .screenRecording: return "screen-recording"
        case .notifications: return "notifications"
        }
    }
    public init?(cliName: String) {
        guard let permission = VelaPermission.allCases.first(where: { $0.cliName == cliName }) else { return nil }
        self = permission
    }
    public var title: String {
        switch self {
        case .accessibility: return "アクセシビリティ"
        case .inputMonitoring: return "入力監視"
        case .screenRecording: return "画面収録"
        case .notifications: return "通知"
        }
    }
    public var detail: String {
        switch self {
        case .accessibility: return "ウィンドウの配置、最小化、終了、切替に使います。"
        case .inputMonitoring: return "どのアプリを使っていてもショートカットを受け取ります。"
        case .screenRecording: return "ウィンドウ切替で内容が分かるプレビューを表示します。"
        case .notifications: return "設定エラーや実行結果を必要な時だけ知らせます。"
        }
    }
    public var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "keyboard"
        case .screenRecording: return "rectangle.on.rectangle"
        case .notifications: return "bell.badge"
        }
    }
}

public final class PermissionCenter {
    public init() {}

    public func refresh(completion: @escaping ([VelaPermission: Bool]) -> Void) {
        var states: [VelaPermission: Bool] = [
            .accessibility: AXIsProcessTrusted(),
            .inputMonitoring: CGPreflightListenEventAccess(),
            .screenRecording: CGPreflightScreenCaptureAccess(),
        ]
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            states[.notifications] = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            completion(states)
        }
    }

    public func request(_ permission: VelaPermission) {
        switch permission {
        case .accessibility:
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }

    public func openPrivacySettings(for permission: VelaPermission) {
        let anchor: String
        switch permission {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .notifications: anchor = "Notifications"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
