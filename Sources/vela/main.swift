import AppKit
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
        case "request":
            requestPermission(arguments.dropFirst().first ?? "all")
        default:
            print("Usage: vela permissions [status | request [all|accessibility|input-monitoring|screen-recording|notifications]]")
        }
    }

    private static func printPermissionStatus() {
        guard let snapshot = PermissionStatusStore.read() else {
            print("Vela の権限状態をまだ確認できません。")
            print("常駐アプリを起動してください: brew services start vela")
            return
        }

        print("Vela の権限")
        for permission in VelaPermission.allCases {
            let granted = snapshot.states[permission.cliName] == true
            let mark = granted ? "✓" : "○"
            let state = granted ? "許可済み" : "未許可"
            print("  \(mark) \(permission.title) — \(state)")
            print("    \(permission.detail)")
        }

        if let next = nextMissingPermission(in: snapshot) {
            print("\n次に行うこと:")
            print("  vela permissions request \(next.cliName)")
        } else {
            print("\nすべての権限が許可されています。")
        }
    }

    private static func requestPermission(_ requestedName: String) {
        guard let snapshot = PermissionStatusStore.read() else {
            print("Vela が起動していません。先に実行してください:")
            print("  brew services start vela")
            return
        }

        let permission: VelaPermission?
        if requestedName == "all" {
            permission = nextMissingPermission(in: snapshot)
        } else {
            permission = VelaPermission(cliName: requestedName)
        }

        guard let permission else {
            if requestedName == "all" {
                print("すべての権限が許可されています。")
            } else {
                fputs("vela: unknown permission: \(requestedName)\n", stderr)
            }
            return
        }

        if snapshot.states[permission.cliName] == true {
            print("\(permission.title) はすでに許可済みです。")
            print("次の権限を進めるには: vela permissions request all")
            return
        }

        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.requestPermission,
            object: nil,
            userInfo: ["permission": permission.cliName],
            deliverImmediately: true
        )
        print("\(permission.title) の許可を要求しました。")
        if permission == .notifications {
            print("macOS の通知ダイアログで「許可」を選んでください。")
        } else {
            print("システム設定の該当ページを開きました。Vela を有効にしてください。")
        }
        print("\n許可した後に実行:")
        print("  vela permissions status")
        print("  vela permissions request all")
    }

    private static func nextMissingPermission(in snapshot: PermissionSnapshot) -> VelaPermission? {
        VelaPermission.allCases.first { snapshot.states[$0.cliName] != true }
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
          permissions       print permission status
          permissions request [name|all]
        """)
    }
}
