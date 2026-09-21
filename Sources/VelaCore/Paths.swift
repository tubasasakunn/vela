import Foundation

public enum VelaPaths {
    public static var defaultConfigDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/vela", directoryHint: .isDirectory)
    }
    public static var configurationLocation: URL {
        defaultConfigDirectory.appending(path: "location")
    }
    public static var configDirectory: URL {
        let override = ProcessInfo.processInfo.environment["VELA_CONFIG_HOME"]
        if let override, !override.isEmpty { return URL(fileURLWithPath: override, isDirectory: true) }
        guard let storedPath = try? String(contentsOf: configurationLocation, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !storedPath.isEmpty else { return defaultConfigDirectory }
        return URL(fileURLWithPath: storedPath, isDirectory: true)
    }
    public static var configuration: URL { configDirectory.appending(path: "vela.js") }

    public static func useConfigurationDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: defaultConfigDirectory, withIntermediateDirectories: true)
        try directory.standardizedFileURL.path.write(to: configurationLocation, atomically: true, encoding: .utf8)
    }
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Vela", directoryHint: .isDirectory)
    }
    public static var clipboardHistory: URL { applicationSupport.appending(path: "clipboard.json") }
}
