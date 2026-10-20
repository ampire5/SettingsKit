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
            Table(shown, selection: $selection) {
                TableColumn("Input") { Text($0.input) }
                    .width(min: 120, ideal: 180)
                TableColumn("Action") { Text($0.action) }
                    .width(min: 160, ideal: 260)
                TableColumn("Source") { row in
                    Text(row.source).foregroundStyle(row.canRestore ? AnyShapeStyle(.primary) : style.secondaryText)
                }
                .width(min: 84, ideal: 92, max: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(TableCornerRemover())
            .contextMenu(forSelectionType: String.self) { ids in
                contextMenu(ids)
            } primaryAction: { ids in
                if let id = Self.editTarget(rows, ids: ids) { edit(id) }
            }
            .onDeleteCommand { removeSelected() }
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

    @ViewBuilder private func contextMenu(_ ids: Set<String>) -> some View {
        let picked = rows.filter { ids.contains($0.id) }
        if let id = Self.editTarget(picked, ids: ids) {
            Button("Edit…") { edit(id) }
        }
        if !picked.isEmpty {
            Button(picked.count == 1 ? "Unbind" : "Unbind \(picked.count) Inputs") { remove(ids) }
                .disabled(!picked.contains { $0.canRemove })
            if picked.contains(where: \.canRestore) {
                Button("Restore Built-in") { restore(picked.filter(\.canRestore)) }
            }
        }
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

/// Takes the corner view off the table next to it: with the content background hidden, the corner above the
/// vertical scroller kept an opaque dark square at the end of the header. AppKit makes the corner view when the
/// scroller first appears (after the rows arrive), so it is taken off again whenever the table's frame changes. The
/// table is the nearest `NSTableView` around this view.
struct TableCornerRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> CornerRemoverView { CornerRemoverView() }
    func updateNSView(_ view: CornerRemoverView, context: Context) { view.attach() }

    final class CornerRemoverView: NSView {
        private weak var table: NSTableView?
        private nonisolated(unsafe) var observer: NSObjectProtocol?

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        func attach() {
            if table == nil, let found = findTable() {
                table = found
                found.postsFrameChangedNotifications = true
                observer = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: found, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.removeCorner() }
                }
            }
            removeCorner()
        }

        private func removeCorner() {
            if let table, table.cornerView != nil { table.cornerView = nil }
        }

        /// The table this view is the background of: among the tables under the nearest ancestor that has any, the
        /// smallest whose scroll view (in window coordinates) holds this view's centre. A page with several tables
        /// has them all under one ancestor, so the first table found would be the wrong one for all but one.
        private func findTable() -> NSTableView? {
            guard window != nil else { return nil }
            let centre = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var ancestor = superview
            while let view = ancestor {
                var tables: [NSTableView] = []
                Self.collectTables(in: view, depth: 10, into: &tables)
                let holding = tables.compactMap { table -> (NSTableView, CGFloat)? in
                    let box = table.enclosingScrollView ?? table
                    let frame = box.convert(box.bounds, to: nil)
                    return frame.contains(centre) ? (table, frame.width * frame.height) : nil
                }
                if let nearest = holding.min(by: { $0.1 < $1.1 }) { return nearest.0 }
                ancestor = view.superview
            }
            return nil
        }

        private static func collectTables(in view: NSView, depth: Int, into tables: inout [NSTableView]) {
            if let table = view as? NSTableView { tables.append(table); return }
            guard depth > 0 else { return }
            for subview in view.subviews { collectTables(in: subview, depth: depth - 1, into: &tables) }
        }
    }
}
