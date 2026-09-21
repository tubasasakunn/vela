import AppKit
import Foundation

public final class ClipboardHistory: @unchecked Sendable {
    public private(set) var entries: [ClipboardEntry] = []
    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var configuration = ClipboardConfiguration()
    public init() { load() }
    public func start(configuration: ClipboardConfiguration) {
        self.configuration = configuration
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in self?.captureIfNeeded() }
    }
    public func stop() { timer?.invalidate(); timer = nil }
    public func copy(_ entry: ClipboardEntry) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.value, forType: .string) }
    public func clear() { entries.removeAll(); persist() }
    private func captureIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        guard let value = pasteboard.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !configuration.ignoredBundleIdentifiers.contains(source ?? "") else { return }
        guard entries.first?.value != value else { return }
        entries.insert(ClipboardEntry(value: value, sourceBundleIdentifier: source), at: 0)
        entries = Array(entries.prefix(configuration.limit)); persist()
    }
    private func load() {
        guard let data = try? Data(contentsOf: VelaPaths.clipboardHistory), let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else { return }
        entries = decoded
    }
    private func persist() {
        try? FileManager.default.createDirectory(at: VelaPaths.applicationSupport, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: VelaPaths.clipboardHistory, options: .atomic)
    }
}
