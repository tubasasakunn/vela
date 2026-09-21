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
    private struct LegacySnippet: Decodable {
        let id: String
        let title: String
        let content: String
        let folder: String?
    }
    private static func snippets(_ arguments: ArraySlice<String>) throws {
        guard arguments.first == "import-clipy" else {
            print("Usage: vela snippets import-clipy")
            return
        }
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.clipy-app.Clipy/sqlite.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw ConfigurationError.invalid("Clipy database was not found")
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-json", database.path,
            "SELECT s.id, s.title, s.content, f.title AS folder FROM snippets s LEFT JOIN snippetFolders f ON f.id = s.folderID ORDER BY f.\"index\", s.\"index\";",
        ]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try output.fileHandleForReading.readToEnd() else {
            throw ConfigurationError.invalid("Could not read Clipy snippets")
        }
        let records = try JSONDecoder().decode([LegacySnippet].self, from: data)
        let begin = "// Vela Clipy import begin"
        let end = "// Vela Clipy import end"
        let declarations = try records.map { snippet in
            let group = try snippet.folder.map(javascriptString) ?? "null"
            return "Vela.snippet({ id: \(try javascriptString("clipy-\(snippet.id)")), title: \(try javascriptString(snippet.title)), group: \(group), value: \(try javascriptString(snippet.content)), keywords: [] });"
        }.joined(separator: "\n")
        let block = "\(begin)\n\(declarations)\n\(end)"
        let configURL = VelaPaths.configuration.resolvingSymlinksInPath()
        var source = try String(contentsOf: configURL, encoding: .utf8)
        if let start = source.range(of: begin),
           let finish = source.range(of: end, range: start.lowerBound..<source.endIndex) {
            source.replaceSubrange(start.lowerBound..<finish.upperBound, with: block)
        } else {
            source += "\n\n\(block)\n"
        }
        try source.write(to: configURL, atomically: true, encoding: .utf8)
        DistributedNotificationCenter.default().post(name: VelaNotifications.reload, object: nil)
        print("Imported \(records.count) Clipy snippets into \(configURL.path)")
    }
    private static func javascriptString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
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
        guard var snapshot = freshPermissionSnapshot(showProgress: true) else {
            printPermissionStatus()
            return
        }

        print("┌  Vela permissions setup")
        printPermissionRows(snapshot)

        while let permission = nextMissingPermission(in: snapshot) {
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

        if freshPermissionSnapshot(showProgress: true)?.states[permission.cliName] == true {
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
        postOpenSettings(permission)
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

    private static func postOpenSettings(_ permission: VelaPermission) {
        PermissionCenter().openPrivacySettings(for: permission)
        DistributedNotificationCenter.default().postNotificationName(
            VelaNotifications.openPermissionSettings,
            object: nil,
            userInfo: ["permission": permission.cliName],
            deliverImmediately: true
        )
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
            if PermissionStatusStore.read()?.states[permission.cliName] == true { return true }
            if frame.isMultiple(of: 12) { postPermissionRefresh() }
            let elapsed = Date().timeIntervalSince(startedAt)
            let message = elapsed < 10
                ? "\(permission.title)の許可を待っています"
                : "\(permission.title)をシステム設定で有効にしてください"
            renderSpinner(frame: frame, text: message)
            frame += 1
            Thread.sleep(forTimeInterval: 0.08)
        } while Date() < deadline
        return PermissionStatusStore.read()?.states[permission.cliName] == true
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
            let granted = snapshot.states[permission.cliName] == true
            let mark = granted ? green("●") : dim("○")
            let state = granted ? green("許可済み") : dim("待機")
            print("\(mark)  \(permission.title)  \(state)")
        }
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
