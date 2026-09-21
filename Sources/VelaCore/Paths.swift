import Foundation

public enum VelaPaths {
    public static var configDirectory: URL {
        let override = ProcessInfo.processInfo.environment["VELA_CONFIG_HOME"]
        if let override, !override.isEmpty { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/vela", directoryHint: .isDirectory)
    }
    public static var configuration: URL { configDirectory.appending(path: "vela.js") }
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Vela", directoryHint: .isDirectory)
    }
    public static var clipboardHistory: URL { applicationSupport.appending(path: "clipboard.json") }
}
