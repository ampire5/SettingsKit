import AppKit
import Foundation
import SwiftUI

// A settings window is described as data: page → section → card → row. The views, the search index and an
// app's coverage tests are all built from the same description.

/// One page of the sidebar.
public struct SettingsPage: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// SF Symbol name.
    public let symbol: String
    public let sections: [SettingsSection]

    public init(_ id: String, _ title: String, symbol: String, sections: [SettingsSection]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.sections = sections
    }

    /// Every row of the page in display order, nested and expanding rows included.
    public var rows: [SettingsRow] { sections.flatMap(\.rows) }

    /// The rows' keys, in order.
    public var keys: [String] { rows.compactMap(\.key) }
}

/// A sub-section: a heading and its cards; also an entry under the page in the sidebar.
public struct SettingsSection: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let cards: [SettingsCard]

    public init(_ title: String, _ cards: [SettingsCard]) {
        self.title = title
        self.cards = cards
    }

    /// A section with a single card.
    public init(_ title: String, rows: [SettingsRow]) {
        self.init(title, [SettingsCard(rows)])
    }

    /// Every row of the section, nested and expanding rows included.
    public var rows: [SettingsRow] { cards.flatMap { $0.rows.flatMap(\.flattened) } }
}

/// A rounded group of rows.
public struct SettingsCard: Sendable {
    public let rows: [SettingsRow]

    public init(_ rows: [SettingsRow]) { self.rows = rows }
}

/// One line of a card. Build rows with the static functions (`.toggle(…)`, `.number(…)`, …).
public struct SettingsRow: Identifiable, Sendable {
    /// The store key the row edits; nil for rows that only group or act (`.group`, `.button`).
    public let key: String?
    public let kind: RowKind
    public let title: String
    /// Secondary text under the title.
    public let description: String?
    /// SF Symbol shown before the title (top-level rows).
    public let symbol: String?
    /// Always-visible dependent rows, indented; inactive while this row is off (`turnsNestedOff`).
    public let nested: [SettingsRow]
    /// Rows behind the chevron of a `.group` row.
    public let expands: [SettingsRow]
    /// The values that turn the nested rows off: for a `.choice` or `.number` row the words listed; a `.toggle` is
    /// off unless `yes`, as long as the set is not empty (an empty set keeps its nested rows active).
    public let offValues: Set<String>
    /// For a `.color` row: value words that stand for colours (`light` → `#ffffff,#cccccc`), so the wells show them.
    public let colorNames: [String: String]

    /// The key, or (for rows without one) the title; unique within a page.
    public var id: String { key ?? "#" + title }

    /// `offValues` nil: `["no"]` for a `.toggle`, none for the other kinds.
    public init(key: String?, kind: RowKind, title: String, description: String? = nil, symbol: String? = nil,
                nested: [SettingsRow] = [], expands: [SettingsRow] = [], offValues: Set<String>? = nil,
                colorNames: [String: String] = [:]) {
        self.key = key
        self.kind = kind
        self.title = title
        self.description = description
        self.symbol = symbol
        self.nested = nested
        self.expands = expands
        if let offValues {
            self.offValues = offValues
        } else if case .toggle = kind {
            self.offValues = ["no"]
        } else {
            self.offValues = []
        }
        self.colorNames = colorNames
    }

    /// Whether `value` of this row makes its nested rows inactive: a switch that is not `yes` (unless its
    /// `offValues` are empty), or a pop-up or number on one of its `offValues`.
    public func turnsNestedOff(value: String) -> Bool {
        switch kind {
        case .toggle: !offValues.isEmpty && value != "yes"
        case .choice, .number: offValues.contains(value)
        default: false
        }
    }

    /// The row followed by its nested and expanding rows (recursively).
    public var flattened: [SettingsRow] {
        [self] + nested.flatMap(\.flattened) + expands.flatMap(\.flattened)
    }
}

/// What a row shows on the right, and how it turns the key's text into a control.
public enum RowKind: Sendable {
    /// `yes` / `no` switch.
    case toggle
    /// A pop-up menu of words (the value) with their titles.
    case choice([(word: String, title: String)])
    /// A right-aligned number field with the unit after it; ↑/↓ step by `step`, ⇧↑/⇧↓ by ten steps.
    case number(unit: String?, step: Double)
    /// A full-width text field under the title.
    case text(placeholder: String?)
    /// A comma list of words: a chevron row that expands into one switch per item.
    case flags(key: String, items: [(word: String, title: String)])
    /// `count` colour wells (`ColorPicker`) and the value as text; the value is `#rrggbb`, comma-separated when
    /// `count` > 1 (`#rgb` is read too).
    case color(count: Int)
    /// A pop-up of icon names (the value) with their images (32 pt in the menu). Asked each time the row is shown.
    case icon(choices: @MainActor @Sendable () -> [(word: String, image: NSImage?)])
    /// A push button with `title`.
    case button(title: String, action: @MainActor @Sendable () -> Void)
    /// A chevron row that expands into its `expands` rows.
    case group
    /// A view of the app's own that fills the card (a table, say): no title, symbol or padding of a row. The search
    /// asks `searchTexts` on every query, so what the view lists can change; the row's title is not shown or searched.
    case custom(searchTexts: @MainActor @Sendable () -> [String], view: @MainActor @Sendable () -> AnyView)
}

// MARK: - Builders

public extension SettingsRow {
    /// `off: []` keeps the nested rows active whatever the switch says (a value that can be on elsewhere, such as
    /// for one folder).
    static func toggle(_ key: String, _ title: String, symbol: String? = nil, description: String? = nil,
                       nested: [SettingsRow] = [], off: Set<String> = ["no"]) -> SettingsRow {
        SettingsRow(key: key, kind: .toggle, title: title, description: description, symbol: symbol, nested: nested,
                    offValues: off)
    }

    /// `off`: the words that turn the nested rows inactive (by default `no`).
    static func choice(_ key: String, _ title: String, _ items: [(word: String, title: String)],
                       symbol: String? = nil, description: String? = nil,
                       nested: [SettingsRow] = [], off: Set<String> = ["no"]) -> SettingsRow {
        SettingsRow(key: key, kind: .choice(items), title: title, description: description, symbol: symbol,
                    nested: nested, offValues: off)
    }

    /// `off`: the values (as the store spells them, e.g. `0`, `no`) that turn the nested rows inactive.
    static func number(_ key: String, _ title: String, unit: String? = nil, step: Double = 1,
                       symbol: String? = nil, description: String? = nil,
                       nested: [SettingsRow] = [], off: Set<String> = []) -> SettingsRow {
        SettingsRow(key: key, kind: .number(unit: unit, step: step), title: title, description: description,
                    symbol: symbol, nested: nested, offValues: off)
    }

    static func text(_ key: String, _ title: String, placeholder: String? = nil, symbol: String? = nil,
                     description: String? = nil, nested: [SettingsRow] = []) -> SettingsRow {
        SettingsRow(key: key, kind: .text(placeholder: placeholder), title: title, description: description,
                    symbol: symbol, nested: nested)
    }

    static func flags(_ key: String, _ title: String, _ items: [(word: String, title: String)],
                      symbol: String? = nil, description: String? = nil) -> SettingsRow {
        SettingsRow(key: key, kind: .flags(key: key, items: items), title: title, description: description,
                    symbol: symbol)
    }

    /// `count` colour wells (`checker-colors` has 2) over a `#rrggbb[,#rrggbb]` value, with the text beside them.
    /// `names`: value words and the colours they stand for (`light` → `#ffffff,#cccccc`), shown in the wells.
    static func color(_ key: String, _ title: String, count: Int = 1, names: [String: String] = [:],
                      symbol: String? = nil, description: String? = nil, nested: [SettingsRow] = []) -> SettingsRow {
        SettingsRow(key: key, kind: .color(count: max(1, count)), title: title, description: description,
                    symbol: symbol, nested: nested, colorNames: names)
    }

    /// A pop-up of `choices` (a word and its picture): the value is the word.
    static func icon(_ key: String, _ title: String,
                     choices: @escaping @MainActor @Sendable () -> [(word: String, image: NSImage?)],
                     symbol: String? = nil, description: String? = nil, nested: [SettingsRow] = []) -> SettingsRow {
        SettingsRow(key: key, kind: .icon(choices: choices), title: title, description: description,
                    symbol: symbol, nested: nested)
    }

    /// A row titled `title` with a push button titled `button`.
    static func button(_ title: String, _ button: String, symbol: String? = nil, description: String? = nil,
                       action: @escaping @MainActor @Sendable () -> Void) -> SettingsRow {
        SettingsRow(key: nil, kind: .button(title: button, action: action), title: title, description: description,
                    symbol: symbol)
    }

    static func group(_ title: String, symbol: String? = nil, description: String? = nil,
                      expands: [SettingsRow]) -> SettingsRow {
        SettingsRow(key: nil, kind: .group, title: title, description: description, symbol: symbol,
                    expands: expands)
    }

    /// A full-width view in its own card (put it alone in a card). `title` names the row (its id) and is not shown;
    /// `searchTexts` are what the window's search finds the row by, asked on every query.
    static func custom<V: View>(_ title: String,
                                searchTexts: @escaping @MainActor @Sendable () -> [String] = { [] },
                                @ViewBuilder view: @escaping @MainActor @Sendable () -> V) -> SettingsRow {
        SettingsRow(key: nil, kind: .custom(searchTexts: searchTexts, view: { AnyView(view()) }), title: title)
    }
}

// MARK: - Colour text

/// The text form of a colour row: `#rrggbb` (lowercase), comma-separated for several colours.
public enum ColorText {
    /// The neutral grey a picker shows (and a missing part is written as) when its text cannot be read.
    public static let neutral = "#808080"

    /// `#rrggbb` of `color` in sRGB, each component rounded to the nearest of 0…255.
    public static func hex(_ color: Color) -> String {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        func byte(_ x: CGFloat) -> Int { x.isFinite ? min(255, max(0, Int((x * 255).rounded()))) : 0 }
        return String(format: "#%02x%02x%02x", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    /// The colours of a comma list of `#rgb` / `#rrggbb` (any case, spaces around parts allowed); nil when
    /// any part cannot be read.
    public static func colors(_ text: String) -> [Color]? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        let colors = parts.compactMap { color(String($0)) }
        return colors.count == parts.count ? colors : nil
    }

    /// One colour of `#rgb` / `#rrggbb`.
    public static func color(_ text: String) -> Color? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        guard digits.hasPrefix("#") else { return nil }
        digits = digits.dropFirst()
        guard digits.count == 3 || digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = Substring(digits.flatMap { [$0, $0] }.map(String.init).joined()) }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        return Color(.sRGB, red: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255,
                     blue: Double(value & 255) / 255, opacity: 1)
    }

    /// What a well shows for part `index` of `text`: that part's colour, or the neutral grey when the part is
    /// missing or cannot be read.
    public static func well(_ text: String, index: Int) -> Color {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        let part = index < parts.count ? String(parts[index]) : ""
        return color(part) ?? color(neutral) ?? .gray
    }

    /// `text`, or the colours it names when it is one of `names` (any case, surrounding spaces ignored).
    public static func resolved(_ text: String, names: [String: String]) -> String {
        names[text.trimmingCharacters(in: .whitespaces).lowercased()] ?? text
    }

    /// The value text of `colors`.
    public static func text(_ colors: [Color]) -> String { colors.map(hex).joined(separator: ",") }

    /// `text` with the colour at `index` replaced by `color` (a list of `count` parts). The other parts stay as
    /// they are written, readable or not; a part that is missing is the neutral grey.
    public static func updating(_ text: String, index: Int, to color: Color, count: Int) -> String {
        var parts = text.isEmpty ? [] : text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        while parts.count < max(count, index + 1) { parts.append(neutral) }
        parts[index] = hex(color)
        return parts.prefix(max(count, 1)).joined(separator: ",")
    }
}

// MARK: - Search

/// A search index over row titles, key names, descriptions, flag item titles and section titles, and the texts a
/// `.custom` row gives at the time of the search.
public struct SettingsSearch: Sendable {
    private struct Entry: Sendable {
        let page: String
        let rowID: String
        let texts: [String]
        let section: String
        /// A `.custom` row's texts, asked on every query.
        var dynamicTexts: (@MainActor @Sendable () -> [String])?
    }

    private let entries: [Entry]

    public init(pages: [SettingsPage]) {
        entries = pages.flatMap { page in
            page.sections.flatMap { section in
                section.rows.map { row in
                    if case .custom(let searchTexts, _) = row.kind {
                        return Entry(page: page.id, rowID: row.id, texts: [], section: section.title,
                                     dynamicTexts: searchTexts)
                    }
                    var texts = [row.title]
                    if let key = row.key { texts.append(key) }
                    if let description = row.description { texts.append(description) }
                    if case .flags(_, let items) = row.kind { texts += items.map(\.title) }
                    return Entry(page: page.id, rowID: row.id, texts: texts, section: section.title)
                }
            }
        }
    }

    /// The rows that contain `query` (case- and diacritic-insensitive) in a title, key name, description, flag item,
    /// a custom row's search texts or their section's title, in description order. A blank query matches nothing.
    @MainActor public func matches(_ query: String) -> [(page: String, rowID: String)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return entries.filter { entry in
            entry.section.localizedStandardContains(q) || entry.texts.contains { $0.localizedStandardContains(q) }
                || (entry.dynamicTexts?() ?? []).contains { $0.localizedStandardContains(q) }
        }.map { (page: $0.page, rowID: $0.rowID) }
    }
}
