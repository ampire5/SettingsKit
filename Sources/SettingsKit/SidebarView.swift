import AppKit
import SwiftUI

/// Search field, page list, and the sub-sections of the open page with their indicator.
///
/// A scroll view of rows with the sidebar list's metrics (rows of 28 pt with 4 pt above and below, content 16 pt in,
/// the selection 10 pt in), not a `List`: the stock list is an `NSOutlineView` that diffed its rows and measured their
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
            VStack(alignment: .leading, spacing: 0) {
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
            SearchField(text: $ui.query, onArrow: { ui.selectAdjacent($0) })
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 10)
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
            Image(systemName: page.symbol).resizable().scaledToFit()
                .fontWeight(.bold).frame(width: 20, height: 20)
                .frame(width: 24)
            Text(page.title).fontWeight(.bold)
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background {
            if selected { RoundedRectangle(cornerRadius: 10).fill(SettingsColors.selection).padding(.horizontal, 10) }
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
    private let rowHeight: CGFloat = 22

    var body: some View {
        let titles = page.sections.map(\.title)
        let index = titles.firstIndex(of: ui.currentSection) ?? 0
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .top) {
                Rectangle().fill(SettingsColors.indicatorLine).frame(width: 1).padding(.vertical, 4)
                Circle().fill(Color(white: 0.5)).frame(width: 8, height: 8)
                    .offset(y: rowHeight / 2 - 4 + rowHeight * CGFloat(index))
                    .animation(.linear(duration: 0.1), value: index)
            }
            .frame(width: 16, height: rowHeight * CGFloat(titles.count))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(titles, id: \.self) { title in
                    Button(title) { ui.scrollRequest = title }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.72))  // IINA: 170/255 on the dark sidebar
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
    var onArrow: (Int) -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
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
    /// Sidebar selection: a grey rounded rect (white 12 % in dark, as IINA), not the accent colour.
    static let selection = dynamic(dark: NSColor(white: 1, alpha: 0.12), light: NSColor(white: 0, alpha: 0.08))
    static let indicatorLine = dynamic(dark: NSColor(white: 1, alpha: 0.4), light: NSColor(white: 0, alpha: 0.25))
    /// Card fill over `windowBackgroundColor`, matched by pixels: dark to IINA (the card reads darker than the
    /// page, 25 vs 36 sRGB), light to the grouped form of System Settings (page 255, card 249).
    static let cardFill = dynamic(dark: NSColor(white: 0, alpha: 0.3), light: NSColor(white: 0, alpha: 0.03))

    static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
