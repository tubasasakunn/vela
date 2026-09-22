import AppKit
import SwiftUI

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    let select: (PaletteItem) -> Void
    let close: () -> Void
    @FocusState private var searchFocused: Bool
    var body: some View {
        surface
            .onAppear { searchFocused = true }
            .onChange(of: model.query) { _, _ in model.selectFirstVisible() }
            .onMoveCommand { model.moveSelection($0) }
            .onExitCommand(perform: close)
    }
    @ViewBuilder private var surface: some View {
        let content = VStack(spacing: 0) {
            HStack(spacing: 12) {
                PaletteBrandIcon()
                TextField(model.placeholder, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .focused($searchFocused)
                    .onSubmit { if let item = model.selectedItem { select(item) } }
                Text(model.title).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).frame(height: 64)
            .background(.thinMaterial, in: Capsule())
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider().opacity(0.45)
            results
        }
        .frame(width: model.isWindowSwitcher ? 880 : 680, height: model.isWindowSwitcher ? 540 : 448)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
    @ViewBuilder private var results: some View {
        if let notice = model.notice {
            Label(notice, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        } else if model.filteredItems.isEmpty {
            ContentUnavailableView("Nothing found", systemImage: "magnifyingglass", description: Text("Try a different search."))
        } else {
            if model.isWindowSwitcher {
                windowThumbnailGrid
            } else {
                standardList
            }
        }
    }

    @ViewBuilder private var standardList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.filteredItems) { item in
                        Button { select(item) } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if let icon = item.icon { Image(nsImage: icon).resizable().scaledToFit() }
                                    else { Image(systemName: item.symbol).resizable().scaledToFit().padding(5) }
                                }
                                .frame(width: 30, height: 30).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(1)
                                    if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).frame(height: 50).contentShape(Rectangle())
                            .background(model.selectedID == item.id ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain).id(item.id)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 8)
            }
            .onChange(of: model.selectedID) { _, id in if let id { withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } } }
        }
    }

    @ViewBuilder private var windowThumbnailGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 210), spacing: 14)],
                    spacing: 16
                ) {
                    ForEach(model.filteredItems) { item in
                        Button { select(item) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Group {
                                    if case let .window(window) = item.kind, let preview = window.preview {
                                        Image(nsImage: preview).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: item.symbol).resizable().scaledToFit().padding(42).foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 118)
                                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                HStack(spacing: 7) {
                                    Group {
                                        if let icon = item.icon { Image(nsImage: icon).resizable().scaledToFit() }
                                        else { Image(systemName: item.symbol).resizable().scaledToFit().padding(2) }
                                    }
                                    .frame(width: 18, height: 18).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        if let subtitle = item.subtitle { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                }
                            }
                            .padding(8)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .background(model.selectedID == item.id ? Color.accentColor.opacity(0.16) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(model.selectedID == item.id ? Color.accentColor.opacity(0.85) : .white.opacity(0.08), lineWidth: model.selectedID == item.id ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain).id(item.id)
                    }
                }.padding(16)
            }
            .onChange(of: model.selectedID) { _, id in if let id { withAnimation(.snappy(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) } } }
        }
    }
}

private struct PaletteBrandIcon: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "VelaMenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkle").foregroundStyle(.tint)
            }
        }
        .frame(width: 18, height: 18)
        .foregroundStyle(.tint)
        .accessibilityLabel("Vela")
    }
}
