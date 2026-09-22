import Foundation
import JavaScriptCore

/// Runs a deliberately small JavaScript surface. Configurations can describe Vela actions,
/// but cannot access the network, filesystem, or process environment while loading.
enum JavaScriptConfiguration {
    private struct PartialConfiguration: Decodable {
        var launcher: LauncherConfiguration?
        var clipboard: ClipboardConfiguration?
        var switcher: SwitcherConfiguration?
        var contextSnippets: [ContextSnippetConfiguration]?
    }
    static let defaultSource = """
    // Vela configuration. This file is ordinary JavaScript and belongs in Git.
    Vela.configure({
      launcher: { applicationSearch: true },
      clipboard: { limit: 200, ignoredBundleIdentifiers: ["com.1password.1password"] },
      switcher: { includeMinimizedWindows: false },
      // These are selected from the focused field's accessible label and description.
      contextSnippets: [
        // { name: "Company address", description: "Billing, shipping, or office-address input fields", content: "〒123-4567\\n東京都…" },
      ],
    });

    Vela.hotkey("option+f", Vela.showLauncher);
    Vela.hotkey("command+shift+space", Vela.showLauncher);
    Vela.hotkey("command+shift+v", Vela.showClipboard);
    Vela.hotkey("control+option+o", Vela.captureTextFromScreen);
    Vela.hotkey("option+tab", Vela.showSwitcher);
    Vela.hotkey("command+shift+tab", Vela.showSwitcher);
    Vela.hotkey("option+[", () => Vela.window("leftHalf"));
    Vela.hotkey("option+]", () => Vela.window("rightHalf"));
    Vela.hotkey("option+m", () => Vela.window("toggleMaximize"));
    Vela.hotkey("option+n", () => Vela.window("minimize"));
    Vela.hotkey("option+q", () => Vela.window("close"));
    Vela.hotkey("option+shift+q", Vela.quitFrontmostApplication);
    Vela.hotkey("control+tab", Vela.showSwitcher);
    Vela.hotkey("option+j", () => Vela.window("nextDisplay"));
    Vela.hotkey("option+k", () => Vela.window("previousDisplay"));
    // Vela.hotkey("control+option+space", Vela.showContextSnippets);

    Vela.command({
      id: "open-workspace",
      title: "Open workspace",
      subtitle: "Open the workspace in Finder",
      keywords: ["project", "code"],
      run: () => Vela.shell("open ~/workspace"),
    });

    // Vela.search({ keyword: "g", title: "Google", url: "https://www.google.com/search?q={query}" });

    // Vela.snippet({
    //   id: "signature",
    //   title: "Signature",
    //   group: "Pinned",
    //   value: "Your fixed text",
    //   keywords: ["fixed", "template"],
    // });
    """

    static func load(from url: URL) throws -> VelaConfiguration {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { throw ConfigurationError.invalid("Could not read \(url.path)") }
        guard let context = JSContext() else { throw ConfigurationError.invalid("JavaScript runtime is unavailable") }
        var configuration = VelaConfiguration()
        var hotkeys: [HotkeyConfiguration] = []
        var commands: [CommandConfiguration] = []
        var searches: [SearchConfiguration] = []
        var snippets: [SnippetConfiguration] = []
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }

        let vela = JSValue(newObjectIn: context)!
        let configure: @convention(block) (JSValue) -> Void = { value in
            do {
                let object = try JavaScriptConfiguration.object(
                    from: value,
                    api: "Vela.configure",
                    allowedKeys: ["launcher", "clipboard", "switcher", "contextSnippets"]
                )
                try JavaScriptConfiguration.validateConfigureProperties(object)
                guard JSONSerialization.isValidJSONObject(object) else {
                    throw ConfigurationError.invalid("Vela.configure expects a JSON-compatible object")
                }
                let partial = try JSONDecoder().decode(PartialConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
                if let launcher = partial.launcher { configuration.launcher = launcher }
                if let clipboard = partial.clipboard { configuration.clipboard = clipboard }
                if let switcher = partial.switcher { configuration.switcher = switcher }
                if let contextSnippets = partial.contextSnippets { configuration.contextSnippets = contextSnippets }
            } catch { failure = error.localizedDescription }
        }
        let hotkey: @convention(block) (JSValue, JSValue) -> Void = { keysValue, action in
            guard keysValue.isString, let keys = keysValue.toString() else {
                failure = "Vela.hotkey keys must be a string"
                return
            }
            guard let descriptor = action.call(withArguments: [])?.toDictionary(), let parsed = JavaScriptConfiguration.action(from: descriptor) else { failure = "Vela.hotkey requires an action returned by Vela"; return }
            hotkeys.append(.init(keys: keys.split(separator: "+", omittingEmptySubsequences: false).map(String.init), action: parsed))
        }
        let command: @convention(block) (JSValue) -> Void = { value in
            do {
                _ = try JavaScriptConfiguration.object(
                    from: value,
                    api: "Vela.command",
                    allowedKeys: ["id", "title", "subtitle", "keywords", "run"]
                )
                let id = try JavaScriptConfiguration.requiredString(value, property: "id", api: "Vela.command")
                let title = try JavaScriptConfiguration.requiredString(value, property: "title", api: "Vela.command")
                let subtitle = try JavaScriptConfiguration.optionalString(value, property: "subtitle", api: "Vela.command")
                let keywords = try JavaScriptConfiguration.optionalStringArray(value, property: "keywords", api: "Vela.command")
                guard let run = value.forProperty("run"), run.isObject,
                      let descriptor = run.call(withArguments: [])?.toDictionary(),
                      let action = JavaScriptConfiguration.commandAction(from: descriptor) else {
                    throw ConfigurationError.invalid("Vela.command run must return Vela.shell, Vela.openURL, or Vela.application")
                }
                commands.append(.init(id: id, title: title, subtitle: subtitle, keywords: keywords, action: action))
            } catch {
                failure = error.localizedDescription
            }
        }
        let search: @convention(block) (JSValue) -> Void = { value in
            do {
                _ = try JavaScriptConfiguration.object(
                    from: value,
                    api: "Vela.search",
                    allowedKeys: ["keyword", "title", "subtitle", "url"]
                )
                let keyword = try JavaScriptConfiguration.requiredString(value, property: "keyword", api: "Vela.search")
                let url = try JavaScriptConfiguration.requiredString(value, property: "url", api: "Vela.search")
                let title = try JavaScriptConfiguration.optionalString(value, property: "title", api: "Vela.search") ?? "Search"
                let subtitle = try JavaScriptConfiguration.optionalString(value, property: "subtitle", api: "Vela.search")
                searches.append(.init(keyword: keyword, title: title, subtitle: subtitle, url: url))
            } catch {
                failure = error.localizedDescription
            }
        }
        let snippet: @convention(block) (JSValue) -> Void = { value in
            do {
                _ = try JavaScriptConfiguration.object(
                    from: value,
                    api: "Vela.snippet",
                    allowedKeys: ["id", "title", "value", "group", "keywords"]
                )
                let id = try JavaScriptConfiguration.requiredString(value, property: "id", api: "Vela.snippet")
                let title = try JavaScriptConfiguration.requiredString(value, property: "title", api: "Vela.snippet")
                let text = try JavaScriptConfiguration.requiredString(value, property: "value", api: "Vela.snippet")
                let group = try JavaScriptConfiguration.optionalString(value, property: "group", api: "Vela.snippet")
                let keywords = try JavaScriptConfiguration.optionalStringArray(value, property: "keywords", api: "Vela.snippet")
                snippets.append(.init(id: id, title: title, value: text, group: group, keywords: keywords))
            } catch {
                failure = error.localizedDescription
            }
        }
        let actionObject: @convention(block) (JSValue) -> NSDictionary = { value in
            guard value.isString, let type = value.toString() else { return ["type": "invalid"] }
            return ["type": type]
        }
        let shellAction: @convention(block) (JSValue) -> NSDictionary = { value in
            guard value.isString, let string = value.toString() else { return ["type": "invalid"] }
            return ["type": "shell", "value": string]
        }
        let urlAction: @convention(block) (JSValue) -> NSDictionary = { value in
            guard value.isString, let string = value.toString() else { return ["type": "invalid"] }
            return ["type": "openURL", "value": string]
        }
        let appAction: @convention(block) (JSValue) -> NSDictionary = { value in
            guard value.isString, let string = value.toString() else { return ["type": "invalid"] }
            return ["type": "application", "value": string]
        }
        vela.setObject(configure, forKeyedSubscript: "configure" as NSString)
        vela.setObject(hotkey, forKeyedSubscript: "hotkey" as NSString)
        vela.setObject(command, forKeyedSubscript: "command" as NSString)
        vela.setObject(search, forKeyedSubscript: "search" as NSString)
        vela.setObject(snippet, forKeyedSubscript: "snippet" as NSString)
        vela.setObject(actionObject, forKeyedSubscript: "window" as NSString)
        vela.setObject(shellAction, forKeyedSubscript: "shell" as NSString)
        vela.setObject(urlAction, forKeyedSubscript: "openURL" as NSString)
        vela.setObject(appAction, forKeyedSubscript: "application" as NSString)
        vela.setObject({ ["type": "launcher"] } as @convention(block) () -> NSDictionary, forKeyedSubscript: "showLauncher" as NSString)
        vela.setObject({ ["type": "clipboard"] } as @convention(block) () -> NSDictionary, forKeyedSubscript: "showClipboard" as NSString)
        vela.setObject({ ["type": "switcher"] } as @convention(block) () -> NSDictionary, forKeyedSubscript: "showSwitcher" as NSString)
        vela.setObject({ ["type": "contextSnippets"] } as @convention(block) () -> NSDictionary, forKeyedSubscript: "showContextSnippets" as NSString)
        vela.setObject({ ["type": "captureTextFromScreen"] } as @convention(block) () -> NSDictionary, forKeyedSubscript: "captureTextFromScreen" as NSString)
        vela.setObject({ ["type": "quitFrontmostApplication"] } as @convention(block) () -> NSDictionary, forKeyedSubscript: "quitFrontmostApplication" as NSString)
        context.setObject(vela, forKeyedSubscript: "Vela" as NSString)
        _ = context.evaluateScript(source, withSourceURL: url)
        if let failure { throw ConfigurationError.invalid(failure) }
        configuration.hotkeys = hotkeys
        configuration.commands = commands
        configuration.searches = searches
        configuration.snippets = snippets
        return configuration
    }

    private static func action(from descriptor: [AnyHashable: Any]) -> VelaAction? {
        guard let type = descriptor["type"] as? String else { return nil }
        switch type {
        case "launcher": return .launcher
        case "clipboard": return .clipboard
        case "switcher": return .switcher
        case "contextSnippets": return .contextSnippets
        case "captureTextFromScreen": return .captureTextFromScreen
        case "quitFrontmostApplication": return .quitFrontmostApplication
        case "leftHalf", "rightHalf", "toggleMaximize", "minimize", "close", "nextDisplay", "previousDisplay", "focusPrevious": return .window(WindowAction(rawValue: type)!)
        default: return nil
        }
    }

    private static func commandAction(from descriptor: [AnyHashable: Any]) -> CommandAction? {
        guard let value = descriptor["value"] as? String else { return nil }
        switch descriptor["type"] as? String {
        case "shell": return .shell(value)
        case "openURL": return .openURL(value)
        case "application": return .application(value)
        default: return nil
        }
    }

    private static func object(from value: JSValue, api: String, allowedKeys: Set<String>) throws -> [AnyHashable: Any] {
        guard value.isObject, !value.isNull, !value.isArray, let object = value.toDictionary() else {
            throw ConfigurationError.invalid("\(api) expects an object")
        }
        try validateKeys(of: object, api: api, allowedKeys: allowedKeys)
        return object
    }

    private static func validateKeys(of object: [AnyHashable: Any], api: String, allowedKeys: Set<String>) throws {
        let keys = object.keys.compactMap { $0 as? String }
        guard keys.count == object.count else { throw ConfigurationError.invalid("\(api) property names must be strings") }
        let unsupported = Set(keys).subtracting(allowedKeys).sorted()
        guard unsupported.isEmpty else {
            throw ConfigurationError.invalid("\(api) contains unsupported property '\(unsupported.joined(separator: "', '"))'")
        }
    }

    private static func validateConfigureProperties(_ object: [AnyHashable: Any]) throws {
        let nestedObjects: [(String, Set<String>)] = [
            ("launcher", ["applicationSearch"]),
            ("clipboard", ["limit", "ignoredBundleIdentifiers"]),
            ("switcher", ["includeMinimizedWindows"]),
        ]
        for (name, allowedKeys) in nestedObjects {
            guard let raw = object[name] else { continue }
            guard let nested = raw as? [AnyHashable: Any] else { continue }
            try validateKeys(of: nested, api: "Vela.configure.\(name)", allowedKeys: allowedKeys)
        }
        guard let rawSnippets = object["contextSnippets"] as? [Any] else { return }
        for (index, rawSnippet) in rawSnippets.enumerated() {
            guard let snippet = rawSnippet as? [AnyHashable: Any] else { continue }
            try validateKeys(
                of: snippet,
                api: "Vela.configure.contextSnippets[\(index)]",
                allowedKeys: ["name", "description", "content"]
            )
        }
    }

    private static func requiredString(_ object: JSValue, property: String, api: String) throws -> String {
        guard let value = object.forProperty(property), value.isString, let string = value.toString() else {
            throw ConfigurationError.invalid("\(api).\(property) must be a string")
        }
        return string
    }

    private static func optionalString(_ object: JSValue, property: String, api: String) throws -> String? {
        guard let value = object.forProperty(property), !value.isUndefined, !value.isNull else { return nil }
        guard value.isString, let string = value.toString() else {
            throw ConfigurationError.invalid("\(api).\(property) must be a string")
        }
        return string
    }

    private static func optionalStringArray(_ object: JSValue, property: String, api: String) throws -> [String] {
        guard let value = object.forProperty(property), !value.isUndefined, !value.isNull else { return [] }
        guard value.isArray, let array = value.toArray(), array.allSatisfy({ $0 is String }) else {
            throw ConfigurationError.invalid("\(api).\(property) must be an array of strings")
        }
        return array.compactMap { $0 as? String }
    }
}
