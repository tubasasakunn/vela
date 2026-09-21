import AppKit
import Foundation

public enum CommandExecutor {
    @discardableResult public static func run(_ command: CommandConfiguration) throws -> Process? {
        switch command.action {
        case let .shell(script):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script]
            try process.run()
            return process
        case let .openURL(raw):
            guard let url = URL(string: raw) else { throw ConfigurationError.invalid("Invalid URL in command \(command.id): \(raw)") }
            NSWorkspace.shared.open(url); return nil
        case let .application(bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { throw ConfigurationError.invalid("Application not found: \(bundleIdentifier)") }
            NSWorkspace.shared.openApplication(at: url, configuration: .init()); return nil
        }
    }
}

public enum VelaNotifications {
    public static let reload = Notification.Name("dev.vela.reload")
}
