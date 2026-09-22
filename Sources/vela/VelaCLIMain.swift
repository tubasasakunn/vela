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
                try runInitialSetup(arguments.dropFirst())
            case "check":
                _ = try ConfigurationStore().load()
                TerminalUI.success("設定を確認しました")
            case "reload":
                try reload()
            case "doctor": doctor()
            case "open":
                try FileManager.default.createDirectory(at: VelaPaths.configDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.open(VelaPaths.configDirectory)
                TerminalUI.success("設定フォルダを開きました")
            case "show": show(arguments.dropFirst())
            case "run": try run(arguments.dropFirst())
            case "clipboard": clipboard(arguments.dropFirst())
            case "snippets": try snippets(arguments.dropFirst())
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
        TerminalUI.heading("Vela の状態")
        if config == "found" { TerminalUI.success("設定") } else { TerminalUI.warning("設定が見つかりません") }
        TerminalUI.detail(VelaPaths.configuration.path)
        if AXIsProcessTrusted() { TerminalUI.success("アクセシビリティ") } else { TerminalUI.action("vela permissions setup") }
        if FileManager.default.fileExists(atPath: VelaPaths.clipboardHistory.path) { TerminalUI.success("クリップボード履歴") }
    }

    private static func run(_ arguments: ArraySlice<String>) throws {
        guard let id = arguments.first else { throw ConfigurationError.invalid("Usage: vela run <command-id>") }
        let config = try ConfigurationStore().load()
        guard let command = config.commands.first(where: { $0.id == id }) else { throw ConfigurationError.invalid("Unknown command: \(id)") }
        if let process = try CommandExecutor.run(command) {
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ConfigurationError.invalid("Command '\(id)' exited with status \(process.terminationStatus)")
            }
        }
    }

    private static func reload() throws {
        _ = try ConfigurationStore().load()
        let requestID = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        var response: Result<Void, Error>?
        let observer = center.addObserver(forName: VelaNotifications.reloadResult, object: nil, queue: nil) { notification in
            guard notification.userInfo?["requestID"] as? String == requestID else { return }
            if notification.userInfo?["success"] as? Bool == true {
                response = .success(())
            } else {
                let message = notification.userInfo?["error"] as? String ?? "The Vela app rejected the configuration"
                response = .failure(ConfigurationError.invalid(message))
            }
        }
        defer { center.removeObserver(observer) }
        let deadline = Date().addingTimeInterval(3)
        var nextRequestDate = Date.distantPast
        while response == nil, Date() < deadline {
            if Date() >= nextRequestDate {
                center.postNotificationName(
                    VelaNotifications.reload,
                    object: nil,
                    userInfo: ["requestID": requestID],
                    deliverImmediately: true
                )
                nextRequestDate = Date().addingTimeInterval(0.25)
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard let response else {
            throw ConfigurationError.invalid("Vela is not running or did not respond; the configuration is valid but was not reloaded")
        }
        try response.get()
        TerminalUI.success("設定を再読み込みしました")
    }

    private static func clipboard(_ arguments: ArraySlice<String>) {
        guard arguments.first == "list" else { usage(); return }
        guard let data = try? Data(contentsOf: VelaPaths.clipboardHistory), let entries = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        for entry in entries { print("\(entry.id.uuidString)\t\(entry.value.replacingOccurrences(of: "\n", with: " "))") }
    }

    private static func show(_ arguments: ArraySlice<String>) {
        guard let mode = arguments.first, ["search", "clipboard", "windows", "context"].contains(mode) else {
            TerminalUI.action("vela show <search|clipboard|windows|context>")
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.showOverlay,
            object: nil,
            userInfo: ["mode": mode],
            deliverImmediately: true
        )
        TerminalUI.success("\(mode) を表示しました")
    }

    private static func usage() {
        TerminalUI.heading("vela")
        print("""
          Usage: vela <command>
          init [--directory <path>]
                            create vela.js and AI setup instructions
          check             validate the configuration
          reload            reload the running Vela app
          doctor            show configuration and permission status
          open              open the configuration directory
          show <mode>       show search, clipboard, or windows
          run <id>          run a configured command
          clipboard list    print clipboard history
          snippets import-clipy
                            import fixed text from Clipy
          permissions       show permission status
          permissions setup configure permissions interactively
        """)
    }
}
