import AppKit
import SwiftUI

/// Search field, page list, and the sub-sections of the open page with their indicator.
///
/// A scroll view of rows with the sidebar list's metrics (32 pt rows separated by 4 pt, content 16 pt in), not a `List`: the stock list is an `NSOutlineView` that diffed its rows and measured their
/// heights on every page switch (the open page's sub-sections are rows that come and go), a third of a return to a
/// page (LoupeBench settings, M4 Max).
struct SidebarView: View {
    @Environment(SettingsUIState.self) private var ui
    @Environment(\.settingsStyle) private var style
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var ui = ui
        // No selection colour of the system: the stock sidebar selection is accent blue while the window is key; the
        // selected page gets its own grey background, and ↑/↓ are handled here.
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ui.visiblePages) { page in
                    SidebarRow(page: page, selected: page.id == ui.page) {
                        ui.select(page.id)
                        listFocused = true
                    }
                    if page.id == ui.page {
                        SubsectionIndicator(page: page)
                            .padding(.horizontal, 16).padding(.vertical, 4)
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listFocused)
        .onKeyPress(.upArrow) { ui.selectAdjacent(-1); return .handled }
        .onKeyPress(.downArrow) { ui.selectAdjacent(1); return .handled }
        .safeAreaInset(edge: .top, spacing: 0) {
            // .searchable(placement: .sidebar) looks the same but sits 9 pt lower and cannot be moved.
            SearchField(text: $ui.query, dark: style == .glass, onArrow: { ui.selectAdjacent($0) })
                .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 8)
        }
        .sidebarSurface(style)
    }
}

/// A page in the sidebar: its symbol and title; the selected one on a grey rounded background.
struct SidebarRow: View {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: page.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
            Spacer(minLength: 0)
        }
        .frame(height: 32)
        .padding(.horizontal, 16)
        .background {
            if selected { RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.10)).padding(.horizontal, 8) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}

/// The open page's sub-sections: a thin line with a dot on the current one; a click scrolls to it.
struct SubsectionIndicator: View {
    @Environment(SettingsUIState.self) private var ui
    let page: SettingsPage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let rowHeight: CGFloat = 24

    var body: some View {
        let titles = page.sections.map(\.title)
        let index = titles.firstIndex(of: ui.currentSection) ?? 0
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .top) {
                Rectangle().fill(.primary.opacity(0.22)).frame(width: 1).padding(.vertical, 4)
                Circle().fill(.primary.opacity(0.65)).frame(width: 6, height: 6)
                    .offset(y: rowHeight / 2 - 3 + rowHeight * CGFloat(index))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: index)
            }
            .frame(width: 16, height: rowHeight * CGFloat(titles.count))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(titles, id: \.self) { title in
                    Button(title) { ui.scrollRequest = title }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: title == ui.currentSection ? .medium : .regular))
                        .foregroundStyle(.primary.opacity(title == ui.currentSection ? 1 : 0.72))
                        .frame(height: rowHeight, alignment: .center)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 2)
    }
}

/// A large `NSSearchField` (IINA's size and position), focused when the window opens.
/// ↑/↓ in the field move between pages.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let dark: Bool
    var onArrow: (Int) -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        if dark { field.appearance = NSAppearance(named: .darkAqua) }
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        field.placeholderString = "Search"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.stringValue = text
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSSearchField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onArrow(-1); return true
            case #selector(NSResponder.moveDown(_:)): parent.onArrow(1); return true
            default: return false
            }
        }
    }
}

/// Colours that differ between the dark and light appearance.
enum SettingsColors {
    /// Opaque neutral surfaces, slightly raised in dark mode and recessed in light mode.
    static let cardFill = dynamic(dark: NSColor(white: 0.17, alpha: 1), light: NSColor(white: 0.97, alpha: 1))

    static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
