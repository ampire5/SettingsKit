import AppKit
import Combine
import SwiftUI

/// One row of a key binding table: an input, what it does and where the binding comes from, as the app words them.
public struct KeyBindingRowModel: Identifiable, Hashable, Sendable {
    /// The input as the app writes it (`f`, `MX_PANEL+WHEEL`): what `remove` and `restoreBuiltIn` are given.
    public let id: String
    /// The Input column (`⇧L`, `Panel + wheel`).
    public let input: String
    /// The Action column (`Fit to window`, `Vibrance amount ±0.05`).
    public let action: String
    /// The Source column (`built-in`, `input.conf`, `off`).
    public let source: String
    public let isMouse: Bool
    /// The action pop-up's item for the row (one of `actionGroups()`), nil when the input is unbound.
    public let actionID: String?
    /// The step of an action that takes one.
    public let step: Double?
    /// The row comes from the app's file: «Restore Built-in» gives the input back to the built-in layout.
    public let canRestore: Bool
    /// «−» and Delete can act on the row (an input that is already off cannot be removed again).
    public let canRemove: Bool
    /// A double-click or «Edit…» opens the sheet on it; false for a binding the app shows but does not keep in its
    /// file (a menu's shortcut).
    public let isEditable: Bool

    public init(id: String, input: String, action: String, source: String, isMouse: Bool, actionID: String? = nil,
                step: Double? = nil, canRestore: Bool = false, canRemove: Bool = true, isEditable: Bool = true) {
        self.id = id
        self.input = input
        self.action = action
        self.source = source
        self.isMouse = isMouse
        self.actionID = actionID
        self.step = step
        self.canRestore = canRestore
        self.canRemove = canRemove
        self.isEditable = isEditable
    }
}

/// Why the key recorder does not take a press: the line shown under it.
public struct KeyBindingRefusal: Error, Equatable, Sendable {
    public let text: String
    public init(_ text: String) { self.text = text }
}

/// What a key binding table shows and edits: the app's bindings and the words of its file. After a change of its own
/// (or one it noticed in the file) the source posts `.settingsStoreDidChange` with itself as the object.
@MainActor public protocol KeyBindingSource: AnyObject {
    /// Every row, keys and mouse; a table shows those of its kind.
    func rows() -> [KeyBindingRowModel]
    /// The sheet's action pop-up, by group. An action that `takesStep` gets a step field (0.01…1 in size).
    func actionGroups() -> [(group: String, actions: [(id: String, title: String, takesStep: Bool)])]
    /// The sheet's button pop-up.
    func mouseButtons() -> [(id: String, title: String)]
    /// The ways a button can be pressed; `id` is the whole input (`MX_PANEL-long`), `enabled` false where the app does
    /// not take that combination.
    func pressKinds(for button: String) -> [(id: String, title: String, enabled: Bool)]
    /// The input a key press records, or why it is refused.
    func keyToken(for event: NSEvent) -> Result<String, KeyBindingRefusal>
    /// The title of the action the input does now, which a new binding would replace; nil when it does nothing.
    func conflict(input: String) -> String?
    func bind(input: String, action: String, step: Double?) throws
    /// «−»: a built-in binding is switched off, a line of the file is commented out.
    func remove(rowID: String) throws
    /// «Restore Built-in»: the file's line for the input is commented out.
    func restoreBuiltIn(rowID: String) throws
}

/// A table of bindings (keys or mouse) with a filter field above it, «+» and «−» below it, a sheet on «+» and on a
/// double-click, «Restore Built-in» in the context menu of a row from the file, and Delete for «−». Reloads when its
/// source posts `.settingsStoreDidChange`. In a settings window the window's search narrows it to the matching rows.
public struct KeyBindingTable: View {
    private let source: KeyBindingSource
    private let mouse: Bool
    private let note: String?
    @Environment(SettingsUIState.self) private var ui: SettingsUIState?
    @Environment(\.settingsStyle) private var style
    @State private var rows: [KeyBindingRowModel] = []
    @State private var filter = ""
    @State private var selection: Set<String> = []
    @State private var draft: KeyBindingDraft?
    @State private var failure: String?

    /// - Parameter note: a line beside «+» and «−» (where the read-only rows are changed).
    public init(source: KeyBindingSource, mouse: Bool, note: String? = nil) {
        self.source = source
        self.mouse = mouse
        self.note = note
    }

    /// The rows that contain `query` (case- and diacritic-insensitive) in the input, as shown or as the file writes it,
    /// the action (its title or id) or the source; every row for a blank query.
    public static func filtered(_ rows: [KeyBindingRowModel], query: String) -> [KeyBindingRowModel] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            [row.input, row.id, row.action, row.source, row.actionID ?? ""].contains { $0.localizedStandardContains(q) }
        }
    }

    /// What the window's search leaves: the matching rows, or every row when none matches (the page was found by its
    /// other table or by a section title).
    static func searched(_ rows: [KeyBindingRowModel], query: String) -> [KeyBindingRowModel] {
        let found = filtered(rows, query: query)
        return found.isEmpty ? rows : found
    }

    /// What «−» and Delete act on: the selected rows the table shows (a filter may hide selected ones) that can be
    /// removed.
    static func removalTargets(shown: [KeyBindingRowModel], selection: Set<String>) -> [KeyBindingRowModel] {
        shown.filter { selection.contains($0.id) && $0.canRemove }
    }

    /// The row a double-click or «Edit…» opens the sheet on: the one picked, if it is editable.
    static func editTarget(_ rows: [KeyBindingRowModel], ids: Set<String>) -> String? {
        guard ids.count == 1, let id = ids.first, rows.contains(where: { $0.id == id && $0.isEditable }) else { return nil }
        return id
    }

    private var shown: [KeyBindingRowModel] {
        let searched = ui?.isSearching == true ? Self.searched(rows, query: ui?.query ?? "") : rows
        return Self.filtered(searched, query: filter)
    }

    public var body: some View {
        VStack(spacing: 0) {
            FilterField(text: $filter)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            BindingsTableView(rows: shown, selection: $selection,
                              sourceColor: style == .glass ? NSColor.labelColor.withAlphaComponent(0.75)
                                                           : .secondaryLabelColor,
                              menu: contextActions, edit: { ids in
                                  if let id = Self.editTarget(rows, ids: ids) { edit(id) }
                              }, delete: removeSelected)
            .frame(height: mouse ? 300 : 420)
            Divider()
            HStack(spacing: 0) {
                Button { add() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    .help(mouse ? "Bind a mouse button" : "Bind a key")
                Divider().frame(height: 16)
                Button { removeSelected() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                    .help("Unbind the selected rows")
                    .disabled(Self.removalTargets(shown: shown, selection: selection).isEmpty)
                Spacer()
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(style.secondaryText)
                        .padding(.trailing, 4)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .settingsStoreDidChange, object: source)) { _ in
            reload()
        }
        .sheet(item: $draft) { start in
            KeyBindingSheet(source: source, draft: start) { saved in
                draft = nil
                if let saved { save(saved) }
            }
        }
        .alert("Couldn't change the binding", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    /// The context menu of the rows `ids` (the clicked row, or the selection it is in).
    private func contextActions(_ ids: Set<String>) -> [BindingsTableView.MenuAction] {
        let picked = rows.filter { ids.contains($0.id) }
        var actions: [BindingsTableView.MenuAction] = []
        if let id = Self.editTarget(picked, ids: ids) {
            actions.append(.init(title: "Edit…") { edit(id) })
        }
        if !picked.isEmpty {
            actions.append(.init(title: picked.count == 1 ? "Unbind" : "Unbind \(picked.count) Inputs",
                                 enabled: picked.contains { $0.canRemove }) { remove(ids) })
            if picked.contains(where: \.canRestore) {
                actions.append(.init(title: "Restore Built-in") { restore(picked.filter(\.canRestore)) })
            }
        }
        return actions
    }

    private func reload() {
        rows = source.rows().filter { $0.isMouse == mouse }
        selection.formIntersection(rows.map(\.id))
    }

    private func add() {
        draft = KeyBindingDraft(isMouse: mouse)
        if mouse, let first = source.mouseButtons().first { draft?.select(button: first.id, in: source) }
    }

    private func edit(_ id: String) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        draft = KeyBindingDraft(editing: row, source: source)
    }

    /// OK writes, except for an edit that changed nothing (a built-in row would gain a line of the file for nothing).
    private func save(_ draft: KeyBindingDraft) {
        if let id = draft.editing, let row = rows.first(where: { $0.id == id }), !draft.changes(row, in: source) { return }
        perform { try draft.save(to: source) }
    }

    private func removeSelected() {
        remove(Set(Self.removalTargets(shown: shown, selection: selection).map(\.id)))
    }

    private func remove(_ ids: Set<String>) {
        let targets = rows.filter { ids.contains($0.id) && $0.canRemove }
        perform { for row in targets { try source.remove(rowID: row.id) } }
    }

    private func restore(_ targets: [KeyBindingRowModel]) {
        perform { for row in targets { try source.restoreBuiltIn(rowID: row.id) } }
    }

    private func perform(_ change: () throws -> Void) {
        do { try change() } catch { failure = error.localizedDescription }
        reload()
    }
}

/// The table's filter: a regular-size search field.
struct FilterField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Filter"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: FilterField
        init(parent: FilterField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSSearchField { parent.text = field.stringValue }
        }
    }
}

/// The bindings as an `NSTableView` with plain text cells: Input, Action, Source. SwiftUI's `Table` made a hosting view
/// per cell, 40 ms of the main thread for the 17 visible rows when the Key Bindings page first opened (LoupeBench
/// settings, M4 Max); these cells cost next to nothing. Several rows can be selected; a double-click or Return asks
/// `edit`, Delete asks `delete`, and the context menu is `menu`'s for the clicked row or the selection it is in.
struct BindingsTableView: NSViewRepresentable {
    struct MenuAction {
        let title: String
        var enabled = true
        let perform: @MainActor () -> Void
    }

    let rows: [KeyBindingRowModel]
    @Binding var selection: Set<String>
    /// The Source column's colour for rows that do not come from the app's file.
    let sourceColor: NSColor
    let menu: @MainActor (Set<String>) -> [MenuAction]
    let edit: @MainActor (Set<String>) -> Void
    let delete: @MainActor () -> Void

    private static let columns: [(id: String, title: String, width: CGFloat, min: CGFloat, max: CGFloat)] = [
        ("input", "Input", 180, 120, 10_000), ("action", "Action", 260, 160, 10_000), ("source", "Source", 92, 84, 140),
    ]

    func makeNSView(context: Context) -> NSScrollView {
        let table = BindingsNSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.rowHeight = 24
        // No opaque square above the vertical scroller at the end of the header.
        table.cornerView = nil
        for column in Self.columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column.min
            tableColumn.maxWidth = column.max
            table.addTableColumn(tableColumn)
        }
        let coordinator = context.coordinator
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.onDelete = { coordinator.parent.delete() }
        table.onReturn = { coordinator.parent.edit(coordinator.parent.selection) }
        let menu = NSMenu()
        menu.delegate = coordinator
        table.menu = menu
        coordinator.table = table

        let scroll = BindingsScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        coordinator.show(rows, selection: selection)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.show(rows, selection: selection)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: BindingsTableView
        weak var table: NSTableView?
        private var shown: [KeyBindingRowModel] = []
        private var sourceColor: NSColor?
        /// Set while the table's selection is set from the binding, so it is not written back.
        private var settingSelection = false

        init(parent: BindingsTableView) { self.parent = parent }

        /// Reloads when the rows or the colour changed, and selects `selection`'s rows.
        func show(_ rows: [KeyBindingRowModel], selection: Set<String>) {
            guard let table else { return }
            if rows != shown || parent.sourceColor != sourceColor {
                shown = rows
                sourceColor = parent.sourceColor
                table.reloadData()
            }
            let indexes = IndexSet(shown.indices.filter { selection.contains(shown[$0].id) })
            if table.selectedRowIndexes != indexes {
                settingSelection = true
                table.selectRowIndexes(indexes, byExtendingSelection: false)
                settingSelection = false
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn?.identifier, shown.indices.contains(row) else { return nil }
            let cell = tableView.makeView(withIdentifier: column, owner: nil) as? NSTableCellView ?? {
                let cell = NSTableCellView()
                cell.identifier = column
                let label = NSTextField(labelWithString: "")
                label.lineBreakMode = .byTruncatingTail
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
                return cell
            }()
            let item = shown[row]
            switch column.rawValue {
            case "input": cell.textField?.stringValue = item.input
            case "action": cell.textField?.stringValue = item.action
            default:
                cell.textField?.stringValue = item.source
                cell.textField?.textColor = item.canRestore ? .labelColor : parent.sourceColor
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !settingSelection, let table else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { shown.indices.contains($0) ? shown[$0].id : nil })
            if ids != parent.selection { parent.selection = ids }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard shown.indices.contains(sender.clickedRow) else { return }
            parent.edit([shown[sender.clickedRow].id])
        }

        /// The rows a context menu is for: the selection when the clicked row is in it, otherwise the clicked row.
        private var menuRows: Set<String> {
            guard let table, shown.indices.contains(table.clickedRow) else { return [] }
            let clicked = shown[table.clickedRow].id
            return parent.selection.contains(clicked) ? parent.selection : [clicked]
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            for action in parent.menu(menuRows) {
                let item = NSMenuItem(title: action.title, action: action.enabled ? #selector(menuPicked(_:)) : nil,
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = MenuBox(action.perform)
                item.isEnabled = action.enabled
                menu.addItem(item)
            }
        }

        @objc private func menuPicked(_ item: NSMenuItem) {
            (item.representedObject as? MenuBox)?.perform()
        }

        private final class MenuBox {
            let perform: @MainActor () -> Void
            init(_ perform: @escaping @MainActor () -> Void) { self.perform = perform }
        }
    }
}

/// The bindings table's scroll view: the columns share out its width (no horizontal scrolling).
final class BindingsScrollView: NSScrollView {
    override func layout() {
        super.layout()
        if let table = documentView as? NSTableView, abs(table.frame.width - contentView.bounds.width) > 0.5 {
            table.sizeToFit()
        }
    }
}

/// The bindings table: Delete and ⌫ unbind the selection, Return edits it.
final class BindingsNSTableView: NSTableView {
    var onDelete: () -> Void = {}
    var onReturn: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) }) {
        case NSDeleteCharacter, NSDeleteFunctionKey, NSBackspaceCharacter: onDelete()
        case NSCarriageReturnCharacter, NSEnterCharacter: onReturn()
        default: super.keyDown(with: event)
        }
    }
}
