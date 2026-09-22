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
            let signature = hotkey.keys.map { $0.lowercased() }.sorted().joined(separator: "+")
            guard seen.insert(signature).inserted else { throw ConfigurationError.duplicateHotkey(signature) }
        }
        let ids = config.commands.map(\.id)
        guard Set(ids).count == ids.count else { throw ConfigurationError.invalid("Command ids must be unique") }
        let searchKeywords = config.searches.map { $0.keyword.lowercased() }
        guard Set(searchKeywords).count == searchKeywords.count else { throw ConfigurationError.invalid("Search keywords must be unique") }
        guard config.searches.allSatisfy({
            !$0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.url.components(separatedBy: "{query}").count == 2
                && $0.url(for: "test") != nil
        }) else {
            throw ConfigurationError.invalid("Search keyword and title must not be empty; url must contain one {query} placeholder and form a valid URL")
        }
        let snippetIDs = config.snippets.map(\.id)
        guard Set(snippetIDs).count == snippetIDs.count else { throw ConfigurationError.invalid("Snippet ids must be unique") }
        guard config.snippets.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && !$0.value.isEmpty }) else {
            throw ConfigurationError.invalid("Snippet id, title, and value must not be empty")
        }
        let contextNames = config.contextSnippets.map(\.name)
        guard Set(contextNames).count == contextNames.count else {
            throw ConfigurationError.invalid("Context snippet names must be unique")
        }
        guard config.contextSnippets.allSatisfy({ !$0.name.isEmpty && !$0.content.isEmpty && !$0.description.isEmpty }) else {
            throw ConfigurationError.invalid("Context snippet name, content, and description must not be empty")
        }
        return config
    }
}
