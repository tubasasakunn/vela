import Foundation

public enum ConfigurationError: LocalizedError {
    case missing(URL)
    case invalid(String)
    case duplicateHotkey(String)
    case invalidClipboardLimit
    public var errorDescription: String? {
        switch self {
        case let .missing(url): return "Vela configuration is missing: \(url.path)"
        case let .invalid(message): return message
        case let .duplicateHotkey(keys): return "Hotkey is registered more than once: \(keys)"
        case .invalidClipboardLimit: return "clipboard.limit must be between 1 and 10,000"
        }
    }
}

public final class ConfigurationStore {
    public init() {}
    public func load() throws -> VelaConfiguration {
        let url = VelaPaths.configuration
        guard FileManager.default.fileExists(atPath: url.path) else { throw ConfigurationError.missing(url) }
        do { return try validate(JavaScriptConfiguration.load(from: url)) }
        catch let error as ConfigurationError { throw error }
        catch { throw ConfigurationError.invalid("Could not read \(url.lastPathComponent): \(error.localizedDescription)") }
    }
    public func writeDefault(overwrite: Bool = false) throws {
        let url = VelaPaths.configuration
        try FileManager.default.createDirectory(at: VelaPaths.configDirectory, withIntermediateDirectories: true)
        guard overwrite || !FileManager.default.fileExists(atPath: url.path) else { return }
        try JavaScriptConfiguration.defaultSource.write(to: url, atomically: true, encoding: .utf8)
    }
    @discardableResult public func validate(_ config: VelaConfiguration) throws -> VelaConfiguration {
        guard (1...10_000).contains(config.clipboard.limit) else { throw ConfigurationError.invalidClipboardLimit }
        var seen = Set<String>()
        for hotkey in config.hotkeys {
            let signature = hotkey.keys.map { $0.lowercased() }.sorted().joined(separator: "+")
            guard seen.insert(signature).inserted else { throw ConfigurationError.duplicateHotkey(signature) }
        }
        let ids = config.commands.map(\.id)
        guard Set(ids).count == ids.count else { throw ConfigurationError.invalid("Command ids must be unique") }
        let snippetIDs = config.snippets.map(\.id)
        guard Set(snippetIDs).count == snippetIDs.count else { throw ConfigurationError.invalid("Snippet ids must be unique") }
        guard config.snippets.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.value.isEmpty }) else {
            throw ConfigurationError.invalid("Snippet id, title, and value must not be empty")
        }
        return config
    }
}
