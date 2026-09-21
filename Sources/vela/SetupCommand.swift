import AppKit
import Foundation
import VelaCore

extension VelaCLI {
    static func runInitialSetup(_ arguments: ArraySlice<String>) throws {
        TerminalUI.heading("Vela を設定")

        let requestedDirectory = try initialSetupDirectory(from: arguments)
        let configuration = requestedDirectory?.appending(path: "vela.js") ?? VelaPaths.configuration
        let directory: URL
        if FileManager.default.fileExists(atPath: configuration.path) {
            directory = requestedDirectory ?? VelaPaths.configDirectory
            if requestedDirectory != nil, ProcessInfo.processInfo.environment["VELA_CONFIG_HOME"] == nil {
                try VelaPaths.useConfigurationDirectory(directory)
            }
            TerminalUI.success("設定ファイル")
            TerminalUI.detail(configuration.path)
        } else {
            if let requestedDirectory {
                directory = requestedDirectory
            } else {
                directory = try chooseConfigurationDirectory()
            }
            let destination = directory.appending(path: "vela.js")
            try ConfigurationStore().writeDefault(to: destination)
            if ProcessInfo.processInfo.environment["VELA_CONFIG_HOME"] == nil {
                try VelaPaths.useConfigurationDirectory(directory)
            }
            TerminalUI.success("設定ファイル")
            TerminalUI.detail(destination.path)
        }
        try ConfigurationSkill.write(to: directory)
        TerminalUI.success("AI 設定スキル")
        TerminalUI.detail(directory.appending(path: ".agent/skills/vela-configuration").path)

        guard TerminalUI.isInteractive else {
            TerminalUI.action("vela permissions setup で権限を設定できます")
            return
        }
        runPermissionSetup()
    }

    private static func initialSetupDirectory(from arguments: ArraySlice<String>) throws -> URL? {
        guard !arguments.isEmpty else { return nil }
        guard arguments.count == 2, arguments.first == "--directory", let path = arguments.dropFirst().first else {
            throw ConfigurationError.invalid("Usage: vela init [--directory <path>]")
        }
        guard path.hasPrefix("/") else {
            throw ConfigurationError.invalid("The setup directory must be an absolute path")
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func chooseConfigurationDirectory() throws -> URL {
        if ProcessInfo.processInfo.environment["VELA_CONFIG_HOME"] != nil || !TerminalUI.isInteractive {
            return VelaPaths.configDirectory
        }

        let panel = NSOpenPanel()
        panel.title = "Vela の設定フォルダを選択"
        panel.message = "このフォルダに vela.js を作成します。"
        panel.prompt = "ここに作成"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = VelaPaths.defaultConfigDirectory.deletingLastPathComponent()
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let directory = panel.url else {
            throw ConfigurationError.invalid("設定フォルダの選択を取り消しました")
        }
        return directory.standardizedFileURL
    }
}
