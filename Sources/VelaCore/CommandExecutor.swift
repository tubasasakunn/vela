import AppKit
import Foundation

public enum CommandExecutor {
    @discardableResult
    public static func run(_ command: CommandConfiguration, onFailure: ((Error) -> Void)? = nil) throws -> Process? {
        switch command.action {
        case let .shell(script):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script]
            if let onFailure {
                process.terminationHandler = { process in
                    guard process.terminationStatus != 0 else { return }
                    onFailure(ConfigurationError.invalid("Command '\(command.id)' exited with status \(process.terminationStatus)"))
                }
            }
            try process.run()
            return process
        case let .openURL(raw):
            guard let url = URL(string: raw) else { throw ConfigurationError.invalid("Invalid URL in command \(command.id): \(raw)") }
            guard NSWorkspace.shared.open(url) else { throw ConfigurationError.invalid("Could not open URL in command \(command.id): \(raw)") }
            return nil
        case let .application(bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { throw ConfigurationError.invalid("Application not found: \(bundleIdentifier)") }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                if let error { onFailure?(error) }
            }
            return nil
        }
    }
}

public enum VelaNotifications {
    public static let reload = Notification.Name("dev.vela.reload")
    public static let reloadResult = Notification.Name("dev.vela.reload-result")
    public static let requestPermission = Notification.Name("dev.vela.request-permission")
    public static let openPermissionSettings = Notification.Name("dev.vela.open-permission-settings")
    public static let refreshPermissions = Notification.Name("dev.vela.refresh-permissions")
    public static let showOverlay = Notification.Name("dev.vela.show-overlay")
}
