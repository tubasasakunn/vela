import AppKit
import SwiftUI
import VelaCore

final class PaletteModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var title = "Vela"
    @Published private(set) var placeholder = "Search commands and applications"
    @Published private(set) var items: [PaletteItem] = []
    @Published private(set) var notice: String?
    @Published private(set) var isWindowSwitcher = false
    @Published var selectedID: UUID?
    private var clipboardHistoryItems: [PaletteItem] = []
    private var fixedTextItems: [PaletteItem] = []
    private var fixedTextFolder: PaletteItem?
    private var fixedTextPath: String?
    private var searches: [SearchConfiguration] = []

    func configureLauncher(configuration: VelaConfiguration) {
        reset(title: "Vela", placeholder: "Search commands and applications")
        searches = configuration.searches
        var next = configuration.commands.map { PaletteItem(command: $0) }
        if configuration.launcher.applicationSearch {
            next += settingsItems()
            next += installedApplications()
        }
        items = next
        selectedID = filteredItems.first?.id
    }

    func configureClipboard(entries: [ClipboardEntry], snippets: [SnippetConfiguration]) {
        reset(title: "Clipboard", placeholder: "Search clipboard history")
        clipboardHistoryItems = entries.map(PaletteItem.init(clipboard:))
        fixedTextItems = snippets.map(PaletteItem.init(snippet:))
        fixedTextFolder = snippets.isEmpty ? nil : PaletteItem(snippetFolderCount: snippets.count)
        fixedTextPath = nil
        items = clipboardHistoryItems + (fixedTextFolder.map { [$0] } ?? [])
        selectedID = filteredItems.first?.id
    }

    func configureSwitcher(windows: [VelaWindow], accessibilityTrusted: Bool, screenRecordingAuthorized: Bool) {
        reset(title: "Windows", placeholder: "Search open windows", isWindowSwitcher: true)
        notice = !accessibilityTrusted
            ? "個別のウィンドウとその画面を表示するには「アクセシビリティ」の許可が必要です。システム設定でVelaを許可してから、もう一度Option + Tabを押してください。"
            : !screenRecordingAuthorized
                ? "画面プレビューには「画面収録」の許可が必要です。システム設定でVelaを許可してから、もう一度Option + Tabを押してください。"
                : nil
        if accessibilityTrusted {
            items = windows.map(PaletteItem.init(window:))
        } else {
            items = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !$0.isTerminated }
                .compactMap { application in
                    guard let url = application.bundleURL, let name = application.localizedName else { return nil }
                    return PaletteItem(application: name, url: url, detail: application.bundleIdentifier)
                }
        }
        selectedID = (filteredItems.dropFirst().first ?? filteredItems.first)?.id
    }

    var filteredItems: [PaletteItem] {
        if let search = searchInvocation { return [PaletteItem(search: search.configuration, query: search.query)] }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            let searchable = fixedTextFolder == nil ? items : clipboardHistoryItems + fixedTextItems
            return searchable.filter { $0.searchText.lowercased().localizedCaseInsensitiveContains(term) }
        }
        return items
    }

    private var searchInvocation: (configuration: SearchConfiguration, query: String)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: \.isWhitespace) else { return nil }
        let keyword = String(trimmed[..<separator])
        let searchQuery = trimmed[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty,
              let configuration = searches.first(where: { $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame }) else { return nil }
        return (configuration, searchQuery)
    }

    var selectedItem: PaletteItem? {
        filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
    }

    func selectFirstVisible() { selectedID = filteredItems.first?.id }

    func moveSelection(_ direction: MoveCommandDirection) {
        let visible = filteredItems
        guard !visible.isEmpty else { selectedID = nil; return }
        let current = visible.firstIndex(where: { $0.id == selectedID }) ?? 0
        let step = isWindowSwitcher ? 4 : 1
        switch direction {
        case .right: selectedID = visible[min(current + 1, visible.count - 1)].id
        case .left: selectedID = visible[max(current - 1, 0)].id
        case .down: selectedID = visible[min(current + step, visible.count - 1)].id
        case .up: selectedID = visible[max(current - step, 0)].id
        default: break
        }
    }

    func openFixedText(group: String?) {
        guard fixedTextFolder != nil else { return }
        query = ""
        fixedTextPath = group ?? ""
        title = group ?? "Fixed text"
        placeholder = "Search fixed text"
        if let group {
            items = fixedTextItems.filter { $0.snippetGroup == group }
        } else {
            let ungrouped = fixedTextItems.filter { $0.snippetGroup == nil }
            let groups = Array(Set(fixedTextItems.compactMap(\.snippetGroup))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            // A single imported Clipy folder should not add an otherwise empty
            // navigation step. Multiple folders remain available for browsing.
            if ungrouped.isEmpty, groups.count == 1 {
                openFixedText(group: groups[0])
                return
            }
            items = ungrouped + groups.map(PaletteItem.init(snippetGroup:))
        }
        selectedID = items.first?.id
    }

    @discardableResult
    func navigateBack() -> Bool {
        guard fixedTextPath != nil else { return false }
        query = ""
        let groups = Set(fixedTextItems.compactMap(\.snippetGroup))
        let bypassesRoot = fixedTextItems.allSatisfy { $0.snippetGroup != nil } && groups.count == 1
        if fixedTextPath != "", !bypassesRoot {
            openFixedText(group: nil)
        } else {
            fixedTextPath = nil
            title = "Clipboard"
            placeholder = "Search clipboard history"
            items = clipboardHistoryItems + (fixedTextFolder.map { [$0] } ?? [])
            selectedID = fixedTextFolder?.id ?? items.first?.id
        }
        return true
    }

    private func installedApplications() -> [PaletteItem] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        ]
        var applications: [String: PaletteItem] = [:]
        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let identifier = bundle?.bundleIdentifier
                applications[url.standardizedFileURL.path] = PaletteItem(application: name, url: url, detail: identifier)
            }
        }
        for application in NSWorkspace.shared.runningApplications {
            guard let url = application.bundleURL, let name = application.localizedName else { continue }
            applications[url.standardizedFileURL.path] = PaletteItem(application: name, url: url, detail: application.bundleIdentifier)
        }
        return applications.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func settingsItems() -> [PaletteItem] {
        [
            ("Wi-Fi", "wifi", "x-apple.systempreferences:com.apple.wifi-settings-extension"),
            ("Bluetooth", "bluetooth", "x-apple.systempreferences:com.apple.BluetoothSettings"),
            ("Network", "network", "x-apple.systempreferences:com.apple.Network-Settings.extension"),
            ("Displays", "display", "x-apple.systempreferences:com.apple.Displays-Settings.extension"),
            ("Sound", "speaker.wave.2", "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
            ("Keyboard", "keyboard", "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"),
            ("Privacy & Security", "hand.raised", "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
        ].compactMap { title, symbol, rawURL in
            URL(string: rawURL).map { PaletteItem(settings: title, url: $0, symbol: symbol) }
        }
    }

    private func reset(title: String, placeholder: String, isWindowSwitcher: Bool = false) {
        self.title = title
        self.placeholder = placeholder
        self.isWindowSwitcher = isWindowSwitcher
        notice = nil
        query = ""
        items = []
        clipboardHistoryItems = []
        fixedTextItems = []
        fixedTextFolder = nil
        fixedTextPath = nil
        searches = []
    }
}
