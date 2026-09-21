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
            print("┌  Vela permissions")
            print("│")
            print("◇  状態を取得できません")
            print("│  brew services start vela")
            print("│  を実行してから、もう一度お試しください。")
            print("│")
            print("└  setup paused")
            return
        }

        print("┌  Vela permissions")
        print("│")
        for permission in VelaPermission.allCases {
            let granted = snapshot.isGranted(permission)
            let mark = granted ? "●" : "○"
            let state = granted ? "許可済み" : "未許可"
            print("\(mark)  \(permission.title)  \(state)")
            print("│  \(permission.detail)")
            print("│")
        }

        if let next = snapshot.nextMissingPermission {
            print("◇  次: \(next.title)")
            print("│  vela permissions setup")
            print("│")
            print("└  \(snapshot.grantedCount) / \(VelaPermission.allCases.count) granted")
        } else {
            print("◇  すべての権限が許可されています")
            print("│")
            print("└  setup complete")
        }
    }

    private static func runPermissionSetup() {
        guard var snapshot = freshPermissionSnapshot(showProgress: true) else {
            printPermissionStatus()
            return
        }

        print("┌  Vela permissions setup")
        printPermissionRows(snapshot)

        while let permission = snapshot.nextMissingPermission {
            print("│")
            animateBriefly("\(permission.title)を要求しています")
            postPermissionRequest(permission)

            guard isInteractiveTerminal else {
                print("◇  \(permission.title)の許可を要求しました")
                print("└  vela permissions status")
                return
            }

            guard waitUntilGranted(permission, timeout: 300) else {
                clearAnimatedLine()
                print("◇  \(permission.title)を確認できませんでした")
                print("│  vela permissions open \(permission.cliName)")
                print("└  vela permissions setup で再開できます")
                return
            }
            clearAnimatedLine()
            print("\(green("●"))  \(permission.title)  許可済み")
            snapshot = freshPermissionSnapshot(showProgress: false) ?? snapshot
        }

        print("│")
        print("◇  \(green("すべての権限が許可されました"))")
        print("└  setup complete  \(VelaPermission.allCases.count) / \(VelaPermission.allCases.count)")
    }

    private static func requestSinglePermission(_ name: String) {
        guard let permission = VelaPermission(cliName: name) else {
            fputs("vela: unknown permission: \(name)\n", stderr)
            permissionUsage()
            return
        }

        if freshPermissionSnapshot(showProgress: true)?.isGranted(permission) == true {
            print("\(green("●"))  \(permission.title)  許可済み")
            return
        }

        animateBriefly("\(permission.title)を要求しています")
        postPermissionRequest(permission)
        guard isInteractiveTerminal else {
            print("◇  \(permission.title)の許可を要求しました")
            return
        }
        if waitUntilGranted(permission, timeout: 300) {
            clearAnimatedLine()
            print("\(green("●"))  \(permission.title)  許可済み")
        } else {
            clearAnimatedLine()
            print("◇  vela permissions open \(permission.cliName)")
        }
    }

    private static func openPermissionSettings(_ name: String?) {
        guard let name, let permission = VelaPermission(cliName: name) else {
            fputs("vela: permission name is required\n", stderr)
            permissionUsage()
            return
        }
        PermissionCenter().openPrivacySettings(for: permission)
        print("◇ \(settingsLocation(for: permission)) を開きました。")
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
        guard isInteractiveTerminal else { return }
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let glyph = cyan(frames[frame % frames.count])
        print("\r\u{001B}[2K\(glyph)  \(text)", terminator: "")
        fflush(stdout)
    }

    private static func clearAnimatedLine() {
        guard isInteractiveTerminal else { return }
        print("\r\u{001B}[2K", terminator: "")
        fflush(stdout)
    }

    private static func printPermissionRows(_ snapshot: PermissionSnapshot) {
        print("│")
        for permission in VelaPermission.allCases {
            let granted = snapshot.isGranted(permission)
            let mark = granted ? green("●") : dim("○")
            let state = granted ? green("許可済み") : dim("待機")
            print("\(mark)  \(permission.title)  \(state)")
        }
    }

    private static var isInteractiveTerminal: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
    }

    private static func green(_ text: String) -> String { color(text, code: "32") }
    private static func cyan(_ text: String) -> String { color(text, code: "36") }
    private static func dim(_ text: String) -> String { color(text, code: "2") }
    private static func color(_ text: String, code: String) -> String {
        guard isInteractiveTerminal, ProcessInfo.processInfo.environment["NO_COLOR"] == nil else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
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
        print("Usage:")
        print("  vela permissions status")
        print("  vela permissions setup")
        print("  vela permissions request <name|all>")
        print("  vela permissions open <name>")
    }
}
