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
                guard let object = value.toDictionary(), JSONSerialization.isValidJSONObject(object) else { throw ConfigurationError.invalid("Vela.configure expects an object") }
                let partial = try JSONDecoder().decode(PartialConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
                if let launcher = partial.launcher { configuration.launcher = launcher }
                if let clipboard = partial.clipboard { configuration.clipboard = clipboard }
                if let switcher = partial.switcher { configuration.switcher = switcher }
                if let contextSnippets = partial.contextSnippets { configuration.contextSnippets = contextSnippets }
            } catch { failure = error.localizedDescription }
        }
        let hotkey: @convention(block) (String, JSValue) -> Void = { keys, action in
            guard let descriptor = action.call(withArguments: [])?.toDictionary(), let parsed = JavaScriptConfiguration.action(from: descriptor) else { failure = "Vela.hotkey requires an action returned by Vela"; return }
            hotkeys.append(.init(keys: keys.split(separator: "+").map { String($0) }, action: parsed))
        }
        let command: @convention(block) (JSValue) -> Void = { value in
            guard let id = value.forProperty("id")?.toString(), let title = value.forProperty("title")?.toString(), let run = value.forProperty("run"), run.isObject else { failure = "Vela.command requires id, title, and run"; return }
            guard let descriptor = run.call(withArguments: [])?.toDictionary(), descriptor["type"] != nil else { failure = "Vela.command run must return Vela.shell, Vela.openURL, or Vela.application"; return }
            let subtitle = value.forProperty("subtitle")?.toString()
            let keywords = (value.forProperty("keywords")?.toArray() as? [String]) ?? []
            commands.append(.init(id: id, title: title, subtitle: subtitle, keywords: keywords, action: JavaScriptConfiguration.commandAction(from: descriptor)))
        }
        let search: @convention(block) (JSValue) -> Void = { value in
            guard let keyword = value.forProperty("keyword")?.toString(),
                  let url = value.forProperty("url")?.toString() else {
                failure = "Vela.search requires keyword and url"
                return
            }
            let title = value.forProperty("title")?.toString() ?? "Search"
            let subtitleValue = value.forProperty("subtitle")
            let subtitle = subtitleValue?.isUndefined == true ? nil : subtitleValue?.toString()
            searches.append(.init(keyword: keyword, title: title, subtitle: subtitle, url: url))
        }
        let snippet: @convention(block) (JSValue) -> Void = { value in
            guard let id = value.forProperty("id")?.toString(),
                  let title = value.forProperty("title")?.toString(),
                  let text = value.forProperty("value")?.toString() else {
                failure = "Vela.snippet requires id, title, and value"
                return
            }
            let group = value.forProperty("group")?.toString()
            let keywords = (value.forProperty("keywords")?.toArray() as? [String]) ?? []
            snippets.append(.init(id: id, title: title, value: text, group: group, keywords: keywords))
        }
        let actionObject: @convention(block) (String) -> NSDictionary = { type in ["type": type] }
        let shellAction: @convention(block) (String) -> NSDictionary = { value in ["type": "shell", "value": value] }
        let urlAction: @convention(block) (String) -> NSDictionary = { value in ["type": "openURL", "value": value] }
        let appAction: @convention(block) (String) -> NSDictionary = { value in ["type": "application", "value": value] }
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

    private static func commandAction(from descriptor: [AnyHashable: Any]) -> CommandAction {
        let value = descriptor["value"] as? String ?? ""
        switch descriptor["type"] as? String {
        case "openURL": return .openURL(value)
        case "application": return .application(value)
        default: return .shell(value)
        }
    }
}
