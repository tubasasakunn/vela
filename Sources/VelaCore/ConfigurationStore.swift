import Foundation

public enum ConfigurationError: LocalizedError {
    case missing(URL)
    case invalid(String)
    case duplicateHotkey(String)
    case invalidHotkey(String, String)
    case hotkeyRegistrationFailed(String, OSStatus)
    case invalidClipboardLimit
    public var errorDescription: String? {
        switch self {
        case let .missing(url): return "Vela configuration is missing: \(url.path)"
        case let .invalid(message): return message
        case let .duplicateHotkey(keys): return "Hotkey is registered more than once: \(keys)"
        case let .invalidHotkey(keys, reason): return "Invalid hotkey '\(keys)': \(reason)"
        case let .hotkeyRegistrationFailed(keys, status): return "Could not register hotkey '\(keys)' (macOS error \(status)). It may already be used by macOS or another app."
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
        try writeDefault(to: VelaPaths.configuration, overwrite: overwrite)
    }
    public func writeDefault(to url: URL, overwrite: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard overwrite || !FileManager.default.fileExists(atPath: url.path) else { return }
        try JavaScriptConfiguration.defaultSource.write(to: url, atomically: true, encoding: .utf8)
    }
    @discardableResult public func validate(_ config: VelaConfiguration) throws -> VelaConfiguration {
        guard (1...10_000).contains(config.clipboard.limit) else { throw ConfigurationError.invalidClipboardLimit }
        var seen = Set<String>()
        for hotkey in config.hotkeys {
            let displayName = hotkey.keys.joined(separator: "+")
            let shortcut: HotkeyShortcut
            do {
                shortcut = try HotkeyShortcut(keys: hotkey.keys)
            } catch {
                throw ConfigurationError.invalidHotkey(displayName, error.localizedDescription)
            }
            guard seen.insert(shortcut.canonicalSignature).inserted else {
                throw ConfigurationError.duplicateHotkey(shortcut.canonicalSignature)
            }
        }
        let ids = config.commands.map(\.id)
        guard Set(ids).count == ids.count else { throw ConfigurationError.invalid("Command ids must be unique") }
        guard config.commands.allSatisfy({ command in
            !command.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && command.id == command.id.trimmingCharacters(in: .whitespacesAndNewlines)
                && !command.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.isValid(command.action)
        }) else {
            throw ConfigurationError.invalid("Command id and title must not be blank, ids must not have surrounding whitespace, and actions must have a usable value")
        }
        let searchKeywords = config.searches.map { $0.keyword.lowercased() }
        guard Set(searchKeywords).count == searchKeywords.count else { throw ConfigurationError.invalid("Search keywords must be unique") }
        guard config.searches.allSatisfy({
            !$0.keyword.isEmpty
                && $0.keyword == $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                && !$0.keyword.contains(where: \.isWhitespace)
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.url.components(separatedBy: "{query}").count == 2
                && $0.url(for: "test") != nil
        }) else {
            throw ConfigurationError.invalid("Search keyword must be one non-blank token, title must not be blank, and url must contain one {query} placeholder and form a valid URL")
        }
        let snippetIDs = config.snippets.map(\.id)
        guard Set(snippetIDs).count == snippetIDs.count else { throw ConfigurationError.invalid("Snippet ids must be unique") }
        guard config.snippets.allSatisfy({
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.id == $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ConfigurationError.invalid("Snippet id, title, and value must not be empty")
        }
        let contextNames = config.contextSnippets.map { $0.name.lowercased() }
        guard Set(contextNames).count == contextNames.count else {
            throw ConfigurationError.invalid("Context snippet names must be unique")
        }
        guard config.contextSnippets.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.name == $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ConfigurationError.invalid("Context snippet name, content, and description must not be empty")
        }
        return config
    }

    private static func isValid(_ action: CommandAction) -> Bool {
        switch action {
        case let .shell(command), let .application(command):
            return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let .openURL(raw):
            guard let url = URL(string: raw), let scheme = url.scheme else { return false }
            return !scheme.isEmpty
        }
    }
}
