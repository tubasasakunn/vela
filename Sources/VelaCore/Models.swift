import Foundation

public struct VelaConfiguration: Codable, Equatable {
    public var launcher: LauncherConfiguration
    public var clipboard: ClipboardConfiguration
    public var switcher: SwitcherConfiguration
    public var hotkeys: [HotkeyConfiguration]
    public var commands: [CommandConfiguration]
    public var searches: [SearchConfiguration]
    public var snippets: [SnippetConfiguration]
    /// Text candidates Vela can choose from based on the focused input field.
    public var contextSnippets: [ContextSnippetConfiguration]

    public init(
        launcher: LauncherConfiguration = .init(),
        clipboard: ClipboardConfiguration = .init(),
        switcher: SwitcherConfiguration = .init(),
        hotkeys: [HotkeyConfiguration] = [],
        commands: [CommandConfiguration] = [],
        searches: [SearchConfiguration] = [],
        snippets: [SnippetConfiguration] = [],
        contextSnippets: [ContextSnippetConfiguration] = []
    ) {
        self.launcher = launcher
        self.clipboard = clipboard
        self.switcher = switcher
        self.hotkeys = hotkeys
        self.commands = commands
        self.searches = searches
        self.snippets = snippets
        self.contextSnippets = contextSnippets
    }

    public static let `default` = VelaConfiguration(
        hotkeys: [
            .init(keys: ["option", "f"], action: .launcher),
            .init(keys: ["command", "shift", "space"], action: .launcher),
            .init(keys: ["command", "shift", "v"], action: .clipboard),
            .init(keys: ["control", "option", "o"], action: .captureTextFromScreen),
            .init(keys: ["option", "tab"], action: .switcher),
            .init(keys: ["command", "shift", "tab"], action: .switcher),
        ]
    )
}

public struct LauncherConfiguration: Codable, Equatable {
    public var applicationSearch: Bool
    public init(applicationSearch: Bool = true) { self.applicationSearch = applicationSearch }
}

public struct ClipboardConfiguration: Codable, Equatable {
    public var limit: Int
    public var ignoredBundleIdentifiers: [String]
    public init(limit: Int = 200, ignoredBundleIdentifiers: [String] = []) {
        self.limit = limit
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers
    }
}

public struct SwitcherConfiguration: Codable, Equatable {
    public var includeMinimizedWindows: Bool
    public init(includeMinimizedWindows: Bool = false) { self.includeMinimizedWindows = includeMinimizedWindows }
}

public struct HotkeyConfiguration: Codable, Equatable, Identifiable {
    public var id: String { keys.joined(separator: "+") }
    public var keys: [String]
    public var action: VelaAction
    public init(keys: [String], action: VelaAction) { self.keys = keys; self.action = action }
}

public enum VelaAction: Codable, Equatable {
    case launcher
    case clipboard
    case switcher
    case contextSnippets
    case captureTextFromScreen
    case command(String)
    case window(WindowAction)
    case quitFrontmostApplication

    private enum CodingKeys: String, CodingKey { case type, id, direction }
    private enum Kind: String, Codable { case launcher, clipboard, switcher, contextSnippets, captureTextFromScreen, command, window, quitFrontmostApplication }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .launcher: self = .launcher
        case .clipboard: self = .clipboard
        case .switcher: self = .switcher
        case .contextSnippets: self = .contextSnippets
        case .captureTextFromScreen: self = .captureTextFromScreen
        case .command: self = .command(try container.decode(String.self, forKey: .id))
        case .window: self = .window(try container.decode(WindowAction.self, forKey: .direction))
        case .quitFrontmostApplication: self = .quitFrontmostApplication
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .launcher: try container.encode(Kind.launcher, forKey: .type)
        case .clipboard: try container.encode(Kind.clipboard, forKey: .type)
        case .switcher: try container.encode(Kind.switcher, forKey: .type)
        case .contextSnippets: try container.encode(Kind.contextSnippets, forKey: .type)
        case .captureTextFromScreen: try container.encode(Kind.captureTextFromScreen, forKey: .type)
        case let .command(id): try container.encode(Kind.command, forKey: .type); try container.encode(id, forKey: .id)
        case let .window(direction): try container.encode(Kind.window, forKey: .type); try container.encode(direction, forKey: .direction)
        case .quitFrontmostApplication: try container.encode(Kind.quitFrontmostApplication, forKey: .type)
        }
    }
}

public enum WindowAction: String, Codable, Equatable {
    case leftHalf, rightHalf, toggleMaximize, minimize, close, nextDisplay, previousDisplay, focusPrevious
}

public struct CommandConfiguration: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var keywords: [String]
    public var action: CommandAction
    public init(id: String, title: String, subtitle: String? = nil, keywords: [String] = [], action: CommandAction) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.keywords = keywords; self.action = action
    }
}

/// A keyword-triggered URL search shown when the launcher query begins with that keyword.
public struct SearchConfiguration: Codable, Equatable, Identifiable {
    public var id: String { keyword.lowercased() }
    public var keyword: String
    public var title: String
    public var subtitle: String?
    /// A URL template containing exactly one `{query}` placeholder.
    public var url: String

    public init(keyword: String, title: String = "Search", subtitle: String? = nil, url: String) {
        self.keyword = keyword
        self.title = title
        self.subtitle = subtitle
        self.url = url
    }

    public func url(for query: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: url.replacingOccurrences(of: "{query}", with: encodedQuery))
    }
}

public struct SnippetConfiguration: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var value: String
    public var group: String?
    public var keywords: [String]
    public init(id: String, title: String, value: String, group: String? = nil, keywords: [String] = []) {
        self.id = id
        self.title = title
        self.value = value
        self.group = group
        self.keywords = keywords
    }
}

/// A paste candidate whose description tells the on-device model when it is appropriate.
public struct ContextSnippetConfiguration: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var content: String
    public var description: String

    public init(name: String, content: String, description: String) {
        self.name = name
        self.content = content
        self.description = description
    }
}

public enum CommandAction: Codable, Equatable {
    case shell(String)
    case openURL(String)
    case application(String)

    private enum CodingKeys: String, CodingKey { case type, command, url, bundleIdentifier }
    private enum Kind: String, Codable { case shell, openURL, application }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .shell: self = .shell(try c.decode(String.self, forKey: .command))
        case .openURL: self = .openURL(try c.decode(String.self, forKey: .url))
        case .application: self = .application(try c.decode(String.self, forKey: .bundleIdentifier))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .shell(command): try c.encode(Kind.shell, forKey: .type); try c.encode(command, forKey: .command)
        case let .openURL(url): try c.encode(Kind.openURL, forKey: .type); try c.encode(url, forKey: .url)
        case let .application(id): try c.encode(Kind.application, forKey: .type); try c.encode(id, forKey: .bundleIdentifier)
        }
    }
}

public struct ClipboardEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let value: String
    public let createdAt: Date
    public let sourceBundleIdentifier: String?
    public init(id: UUID = UUID(), value: String, createdAt: Date = .now, sourceBundleIdentifier: String? = nil) {
        self.id = id; self.value = value; self.createdAt = createdAt; self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}
