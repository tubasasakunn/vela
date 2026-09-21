import AppKit
import Darwin
import Foundation
import VelaCore

extension VelaCLI {
    static func permissions(_ arguments: ArraySlice<String>) {
        let action = arguments.first ?? "status"
        switch action {
        case "status":
            printPermissionStatus()
        case "setup":
            runPermissionSetup()
        case "request":
            let target = arguments.dropFirst().first ?? "all"
            if target == "all" { runPermissionSetup() }
            else { requestSinglePermission(target) }
        case "open":
            openPermissionSettings(arguments.dropFirst().first)
        default:
            permissionUsage()
        }
    }

    private static func printPermissionStatus() {
        guard let snapshot = freshPermissionSnapshot(showProgress: true) else {
            TerminalUI.warning("権限の状態を取得できません")
            TerminalUI.action("Vela を開いてから、もう一度実行してください")
            return
        }

        TerminalUI.heading("権限")
        for permission in VelaPermission.allCases {
            let granted = snapshot.isGranted(permission)
            let mark = granted ? TerminalUI.style("✓", code: "32") : TerminalUI.style("○", code: "2")
            print("\(mark)  \(permission.title)")
        }

        if let next = snapshot.nextMissingPermission {
            TerminalUI.action("次は \(next.title)  ·  vela permissions setup")
        } else {
            TerminalUI.success("準備完了")
        }
    }

    static func runPermissionSetup() {
        guard var snapshot = freshPermissionSnapshot(showProgress: true) else {
            printPermissionStatus()
            return
        }

        TerminalUI.heading("権限を設定")
        printPermissionRows(snapshot)

        while let permission = snapshot.nextMissingPermission {
            animateBriefly("\(permission.title)を要求しています")
            postPermissionRequest(permission)

            guard isInteractiveTerminal else {
                TerminalUI.action("\(permission.title)の要求を送信しました")
                return
            }

            guard waitUntilGranted(permission, timeout: 300) else {
                clearAnimatedLine()
                TerminalUI.warning("\(permission.title)を確認できませんでした")
                TerminalUI.action("vela permissions open \(permission.cliName)")
                return
            }
            clearAnimatedLine()
            TerminalUI.success(permission.title)
            snapshot = freshPermissionSnapshot(showProgress: false) ?? snapshot
        }

        TerminalUI.success("セットアップ完了")
    }

    private static func requestSinglePermission(_ name: String) {
        guard let permission = VelaPermission(cliName: name) else {
            fputs("vela: unknown permission: \(name)\n", stderr)
            permissionUsage()
            return
        }

        if freshPermissionSnapshot(showProgress: true)?.isGranted(permission) == true {
            TerminalUI.success(permission.title)
            return
        }

        animateBriefly("\(permission.title)を要求しています")
        postPermissionRequest(permission)
        guard isInteractiveTerminal else {
            TerminalUI.action("\(permission.title)の要求を送信しました")
            return
        }
        if waitUntilGranted(permission, timeout: 300) {
            clearAnimatedLine()
            TerminalUI.success(permission.title)
        } else {
            clearAnimatedLine()
            TerminalUI.action("vela permissions open \(permission.cliName)")
        }
    }

    private static func openPermissionSettings(_ name: String?) {
        guard let name, let permission = VelaPermission(cliName: name) else {
            fputs("vela: permission name is required\n", stderr)
            permissionUsage()
            return
        }
        PermissionCenter().openPrivacySettings(for: permission)
        TerminalUI.success("\(settingsLocation(for: permission)) を開きました")
    }

    private static func postPermissionRequest(_ permission: VelaPermission) {
        ensureVelaIsRunning()
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.requestPermission,
            object: nil,
            userInfo: ["permission": permission.cliName],
            deliverImmediately: true
        )
        PermissionCenter().openPrivacySettings(for: permission)
    }

    private static func ensureVelaIsRunning() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.vela.app") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private static func postPermissionRefresh() {
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.refreshPermissions,
            object: nil,
            deliverImmediately: true
        )
    }

    private static func freshPermissionSnapshot(showProgress: Bool) -> PermissionSnapshot? {
        ensureVelaIsRunning()
        let previousCheck = PermissionStatusStore.read()?.checkedAt ?? .distantPast
        postPermissionRefresh()
        let deadline = Date().addingTimeInterval(3)
        var frame = 0
        repeat {
            if let snapshot = PermissionStatusStore.read(), snapshot.checkedAt > previousCheck {
                if showProgress { clearAnimatedLine() }
                return snapshot
            }
            if showProgress && isInteractiveTerminal {
                renderSpinner(frame: frame, text: "権限を確認しています")
                frame += 1
            }
            Thread.sleep(forTimeInterval: 0.08)
        } while Date() < deadline
        if showProgress { clearAnimatedLine() }
        return PermissionStatusStore.read()
    }

    private static func waitUntilGranted(_ permission: VelaPermission, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let startedAt = Date()
        var frame = 0
        repeat {
            if PermissionStatusStore.read()?.isGranted(permission) == true { return true }
            if frame.isMultiple(of: 12) { postPermissionRefresh() }
            let elapsed = Date().timeIntervalSince(startedAt)
            let message = elapsed < 10
                ? "\(permission.title)の許可を待っています"
                : "\(permission.title)をシステム設定で有効にしてください"
            renderSpinner(frame: frame, text: message)
            frame += 1
            Thread.sleep(forTimeInterval: 0.08)
        } while Date() < deadline
        return PermissionStatusStore.read()?.isGranted(permission) == true
    }

    private static func animateBriefly(_ text: String) {
        guard isInteractiveTerminal else { return }
        for frame in 0..<7 {
            renderSpinner(frame: frame, text: text)
            Thread.sleep(forTimeInterval: 0.06)
        }
        clearAnimatedLine()
    }

    private static func renderSpinner(frame: Int, text: String) {
        TerminalUI.spinner(frame: frame, text: text)
    }

    private static func clearAnimatedLine() {
        TerminalUI.clearLine()
    }

    private static func printPermissionRows(_ snapshot: PermissionSnapshot) {
        for permission in VelaPermission.allCases {
            guard !snapshot.isGranted(permission) else { continue }
            TerminalUI.detail("\(permission.title) — \(permission.detail)")
        }
    }

    private static var isInteractiveTerminal: Bool {
        TerminalUI.isInteractive
    }

    private static func settingsLocation(for permission: VelaPermission) -> String {
        switch permission {
        case .accessibility: return "システム設定 → プライバシーとセキュリティ → アクセシビリティ"
        case .inputMonitoring: return "システム設定 → プライバシーとセキュリティ → 入力監視"
        case .screenRecording: return "システム設定 → プライバシーとセキュリティ → 画面収録"
        case .notifications: return "システム設定 → 通知 → Vela"
        }
    }

    private static func permissionUsage() {
        TerminalUI.heading("permissions")
        print("  vela permissions status")
        print("  vela permissions setup")
        print("  vela permissions request <name|all>")
        print("  vela permissions open <name>")
    }
}
