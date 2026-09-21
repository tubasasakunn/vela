import AppKit
import Foundation
import VelaCore

extension VelaCLI {
    static func runInitialSetup() throws {
        TerminalUI.heading("Vela を設定")

        let configuration = VelaPaths.configuration
        if FileManager.default.fileExists(atPath: configuration.path) {
            TerminalUI.success("設定ファイル")
            TerminalUI.detail(configuration.path)
        } else {
            let directory = try chooseConfigurationDirectory()
            let destination = directory.appending(path: "vela.js")
            try ConfigurationStore().writeDefault(to: destination)
            if ProcessInfo.processInfo.environment["VELA_CONFIG_HOME"] == nil {
                try VelaPaths.useConfigurationDirectory(directory)
            }
            TerminalUI.success("設定ファイル")
            TerminalUI.detail(destination.path)
        }

        guard TerminalUI.isInteractive else {
            TerminalUI.action("vela permissions setup で権限を設定できます")
            return
        }
        runPermissionSetup()
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
