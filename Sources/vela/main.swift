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

    private static func show(_ arguments: ArraySlice<String>) {
        guard let mode = arguments.first, ["search", "clipboard", "windows", "context"].contains(mode) else {
            print("Usage: vela show <search|clipboard|windows|context>")
            return
        }
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.showOverlay,
            object: nil,
            userInfo: ["mode": mode],
            deliverImmediately: true
        )
    }

    private static func usage() {
        print("""
        Usage: vela <command>
          init              create ~/.config/vela/vela.js
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
