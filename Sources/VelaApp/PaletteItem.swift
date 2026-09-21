import AppKit
import Foundation
import VelaCore

struct PaletteItem: Identifiable {
    enum Kind {
        case command(CommandConfiguration)
        case application(URL)
        case settings(URL)
        case clipboard(ClipboardEntry)
        case snippet(SnippetConfiguration)
        case snippetFolder(String?)
        case window(VelaWindow)
    }

    let id = UUID()
    let title: String
    let subtitle: String?
    let symbol: String
    let icon: NSImage?
    let kind: Kind

    var searchText: String {
        let base = title + " " + (subtitle ?? "")
        switch kind {
        case let .command(command): return base + " " + command.keywords.joined(separator: " ")
        case let .snippet(snippet): return base + " " + snippet.keywords.joined(separator: " ")
        default: return base
        }
    }
    var snippetGroup: String? {
        if case let .snippet(snippet) = kind { return snippet.group }
        return nil
    }

    init(command: CommandConfiguration) {
        title = command.title
        subtitle = command.subtitle
        symbol = "terminal"
        icon = nil
        kind = .command(command)
    }

    init(application: String, url: URL, detail: String?) {
        title = application
        subtitle = detail
        symbol = "app"
        icon = NSWorkspace.shared.icon(forFile: url.path)
        kind = .application(url)
    }

    init(settings: String, url: URL, symbol: String) {
        title = settings
        subtitle = "System Settings"
        self.symbol = symbol
        icon = nil
        kind = .settings(url)
    }
    init(clipboard: ClipboardEntry) {
        title = clipboard.value.replacingOccurrences(of: "\n", with: " ")
        let sourceURL = clipboard.sourceBundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        let sourceName = sourceURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
        let relative = RelativeDateTimeFormatter().localizedString(for: clipboard.createdAt, relativeTo: .now)
        subtitle = [sourceName, relative].compactMap { $0 }.joined(separator: " · ")
        symbol = "doc.on.clipboard"
        icon = sourceURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
        kind = .clipboard(clipboard)
    }
    init(snippet: SnippetConfiguration) {
        title = snippet.title
        subtitle = [snippet.group, snippet.value].compactMap { $0 }.joined(separator: " · ")
        symbol = "pin.fill"
        icon = nil
        kind = .snippet(snippet)
    }
    init(snippetFolderCount count: Int) {
        title = "Fixed text"
        subtitle = "\(count) items · Right arrow to expand"
        symbol = "folder"
        icon = nil
        kind = .snippetFolder(nil)
    }
    init(snippetGroup group: String) {
        title = group
        subtitle = "Fixed text folder · Right arrow to open"
        symbol = "folder"
        icon = nil
        kind = .snippetFolder(group)
    }
    init(window: VelaWindow) {
        title = window.title
        subtitle = window.applicationName
        symbol = "macwindow"
        icon = window.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.map { NSWorkspace.shared.icon(forFile: $0.path) }
        kind = .window(window)
    }
}
