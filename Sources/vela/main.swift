import AppKit
import Darwin
import Foundation
import VelaCore

@main
struct VelaCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"
        do {
            switch command {
            case "init":
                try ConfigurationStore().writeDefault()
                print("Created \(VelaPaths.configuration.path)")
            case "check":
                _ = try ConfigurationStore().load()
                print("Configuration is valid.")
            case "reload":
                DistributedNotificationCenter.default().post(name: VelaNotifications.reload, object: nil)
                print("Asked Vela to reload its configuration.")
            case "doctor": doctor()
            case "open":
                try FileManager.default.createDirectory(at: VelaPaths.configDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(VelaPaths.configDirectory)
            case "run": try run(arguments.dropFirst())
            case "clipboard": clipboard(arguments.dropFirst())
            case "permissions": permissions(arguments.dropFirst())
            default: usage()
            }
        } catch {
            fputs("vela: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
    private static func doctor() {
        let config = FileManager.default.fileExists(atPath: VelaPaths.configuration.path) ? "found" : "missing"
        print("Configuration: \(config) (\(VelaPaths.configuration.path))")
        print("Accessibility: \(AXIsProcessTrusted() ? "allowed" : "not allowed")")
        print("Clipboard history: \(FileManager.default.fileExists(atPath: VelaPaths.clipboardHistory.path) ? "available" : "waiting for Vela")")
    }
    private static func run(_ arguments: ArraySlice<String>) throws {
        guard let id = arguments.first else { throw ConfigurationError.invalid("Usage: vela run <command-id>") }
        let config = try ConfigurationStore().load()
        guard let command = config.commands.first(where: { $0.id == id }) else { throw ConfigurationError.invalid("Unknown command: \(id)") }
        try CommandExecutor.run(command)?.waitUntilExit()
    }
    private static func clipboard(_ arguments: ArraySlice<String>) {
        guard arguments.first == "list" else { usage(); return }
        guard let data = try? Data(contentsOf: VelaPaths.clipboardHistory), let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        for entry in entries { print("\(entry.id.uuidString)\t\(entry.value.replacingOccurrences(of: "\n", with: " "))") }
    }
    private static func permissions(_ arguments: ArraySlice<String>) {
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
        guard let snapshot = PermissionStatusStore.read() else {
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
            let granted = snapshot.states[permission.cliName] == true
            let mark = granted ? "●" : "○"
            let state = granted ? "許可済み" : "未許可"
            print("\(mark)  \(permission.title)  \(state)")
            print("│  \(permission.detail)")
            print("│")
        }

        if let next = nextMissingPermission(in: snapshot) {
            print("◇  次: \(next.title)")
            print("│  vela permissions setup")
            print("│")
            print("└  \(grantedCount(in: snapshot)) / \(VelaPermission.allCases.count) granted")
        } else {
            print("◇  すべての権限が許可されています")
            print("│")
            print("└  setup complete")
        }
    }

    private static func runPermissionSetup() {
        guard var snapshot = PermissionStatusStore.read() else {
            printPermissionStatus()
            return
        }

        print("┌  Vela permissions setup")
        print("│  macOS のダイアログと設定画面は同時に開きません。")
        print("│  ひとつずつ状態を確認しながら進めます。")

        var isFirstPermission = true
        while let permission = nextMissingPermission(in: snapshot) {
            if !isFirstPermission && isInteractiveTerminal {
                print("│")
                print("◆  次は \(permission.title) です。続けるには Return、終了は q")
                if readLine()?.lowercased() == "q" {
                    print("│")
                    print("└  setup paused — vela permissions setup で再開できます")
                    return
                }
            }
            isFirstPermission = false

            print("│")
            print("◇  \(permission.title)")
            print("│  \(permission.detail)")
            postPermissionRequest(permission)
            print("│  macOS の許可ダイアログを要求しました。")

            guard isInteractiveTerminal else {
                print("│  状態確認: vela permissions status")
                print("│  ダイアログが出ない場合: vela permissions open \(permission.cliName)")
                print("│")
                print("└  request sent")
                return
            }

            while true {
                print("│")
                print("◆  許可したら Return / 設定を直接開く o / スキップ s / 終了 q")
                let response = readLine()?.lowercased() ?? "q"
                if response == "q" {
                    print("│")
                    print("└  setup paused — vela permissions setup で再開できます")
                    return
                }
                if response == "s" {
                    print("│  \(permission.title) をスキップしました。")
                    print("│")
                    print("└  setup paused — vela permissions setup で再開できます")
                    return
                }
                if response == "o" {
                    postOpenSettings(permission)
                    print("│  \(settingsLocation(for: permission)) を開きました。")
                    continue
                }

                if waitUntilGranted(permission, timeout: 3) {
                    print("│  ● \(permission.title) — 許可済み")
                    snapshot = PermissionStatusStore.read() ?? snapshot
                    break
                }
                print("│  ○ まだ未許可です。Vela を有効にしてから Return を押してください。")
            }
        }

        print("│")
        print("◇  すべての権限が許可されました")
        print("│")
        print("└  setup complete")
    }

    private static func requestSinglePermission(_ name: String) {
        guard let permission = VelaPermission(cliName: name) else {
            fputs("vela: unknown permission: \(name)\n", stderr)
            permissionUsage()
            return
        }

        if PermissionStatusStore.read()?.states[permission.cliName] == true {
            print("● \(permission.title) — すでに許可済み")
            return
        }

        postPermissionRequest(permission)
        print("◇ \(permission.title) の許可ダイアログを要求しました。")
        print("  ダイアログが出ない場合: vela permissions open \(permission.cliName)")
        print("  状態確認: vela permissions status")
    }

    private static func openPermissionSettings(_ name: String?) {
        guard let name, let permission = VelaPermission(cliName: name) else {
            fputs("vela: permission name is required\n", stderr)
            permissionUsage()
            return
        }
        postOpenSettings(permission)
        print("◇ \(settingsLocation(for: permission)) を開きました。")
    }

    private static func postPermissionRequest(_ permission: VelaPermission) {
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.requestPermission,
            object: nil,
            userInfo: ["permission": permission.cliName],
            deliverImmediately: true
        )
    }

    private static func postOpenSettings(_ permission: VelaPermission) {
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.openPermissionSettings,
            object: nil,
            userInfo: ["permission": permission.cliName],
            deliverImmediately: true
        )
    }

    private static func waitUntilGranted(_ permission: VelaPermission, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if PermissionStatusStore.read()?.states[permission.cliName] == true { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return PermissionStatusStore.read()?.states[permission.cliName] == true
    }

    private static func nextMissingPermission(in snapshot: PermissionSnapshot) -> VelaPermission? {
        VelaPermission.allCases.first { snapshot.states[$0.cliName] != true }
    }

    private static func grantedCount(in snapshot: PermissionSnapshot) -> Int {
        VelaPermission.allCases.filter { snapshot.states[$0.cliName] == true }.count
    }

    private static var isInteractiveTerminal: Bool {
        isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
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
    private static func usage() {
        print("""
        Usage: vela <command>
          init              create ~/.config/vela/vela.js
          check             validate the configuration
          reload            reload the running Vela app
          doctor            show configuration and permission status
          open              open the configuration directory
          run <id>          run a configured command
          clipboard list    print clipboard history
          permissions       show permission status
          permissions setup configure permissions interactively
        """)
    }
}
