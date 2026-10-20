import SwiftUI

/// A rounded card: its rows, their nested rows, and the rows of open chevrons, with inset separators.
/// Metrics after IINA 1.5: radius 12, 1 px border in the separator colour, separator inset 36
/// (44 between nested siblings).
struct CardView: View {
    @Environment(SettingsUIState.self) private var ui
    @Environment(SettingsModel.self) private var model
    @Environment(\.settingsStyle) private var style
    let card: SettingsCard

    /// One displayed line: a row, or one item of an open `.flags` row.
    enum Line: Identifiable {
        case row(SettingsRow, nested: Bool, enabled: Bool)
        case flag(key: String, word: String, title: String, enabled: Bool)

        var id: String {
            switch self {
            case .row(let row, _, _): row.id
            case .flag(let key, let word, _, _): "\(key)=\(word)"
            }
        }
        var nested: Bool {
            switch self {
            case .row(_, let nested, _): nested
            case .flag: true
            }
        }
    }

    var body: some View {
        let lines = card.rows.flatMap { lines(for: $0, nested: false, enabled: true) }
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                Group {
                    switch line {
                    case .row(let row, let nested, let enabled):
                        if case .custom(_, let view) = row.kind {
                            view()
                                .disabled(!enabled)
                                .overlay { if ui.isMatch(row.id) { MatchOutline(filled: false).allowsHitTesting(false) } }
                        } else {
                            RowView(row: row, nested: nested, expanded: isExpanded(row)) { toggleExpanded(row) }
                                .disabled(!enabled)
                        }
                    case .flag(let key, let word, let title, let enabled):
                        FlagItemView(key: key, word: word, title: title).disabled(!enabled)
                    }
                }
                .overlay(alignment: .top) {
                    if i > 0 {
                        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                            .padding(.leading, line.nested && lines[i - 1].nested ? 44 : 36)
                    }
                }
            }
        }
        .cardSurface(style)
    }

    /// The row, its nested rows (disabled while the row is off, `turnsNestedOff`), and the content of an open chevron.
    private func lines(for row: SettingsRow, nested: Bool, enabled: Bool) -> [Line] {
        var result: [Line] = [.row(row, nested: nested, enabled: enabled)]
        var childrenEnabled = enabled
        if let key = row.key, row.turnsNestedOff(value: model.value(key)) { childrenEnabled = false }
        result += row.nested.flatMap { lines(for: $0, nested: true, enabled: childrenEnabled) }
        if isExpanded(row) {
            switch row.kind {
            case .group:
                result += row.expands.flatMap { lines(for: $0, nested: true, enabled: enabled) }
            case .flags(let key, let items):
                result += items.map { .flag(key: key, word: $0.word, title: $0.title, enabled: enabled) }
            default: break
            }
        }
        return result
    }

    /// Open by a click, or while searching when something inside matches.
    private func isExpanded(_ row: SettingsRow) -> Bool {
        if ui.expanded.contains(row.id) { return true }
        guard ui.isSearching else { return false }
        switch row.kind {
        case .group: return row.expands.flatMap(\.flattened).contains { ui.isMatch($0.id) }
        case .flags(_, let items): return items.contains { ui.queryMatches($0.title) }
        default: return false
        }
    }

    private func toggleExpanded(_ row: SettingsRow) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if ui.expanded.contains(row.id) { ui.expanded.remove(row.id) } else { ui.expanded.insert(row.id) }
        }
    }
}
