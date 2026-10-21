import AppKit
import SwiftUI

/// One row: symbol (or indent), title, description (or the key's error in red), and the kind's control.
/// Row 40 pt (nested 32): vertical padding 12 (8) around a 16 pt line; the control is centred on the
/// title's line and never grows the row. Text at x 36 (nested 44) from the card edge.
struct RowView: View {
    @Environment(SettingsUIState.self) private var ui
    @Environment(SettingsModel.self) private var model
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.settingsStyle) private var style
    let row: SettingsRow
    let nested: Bool
    let expanded: Bool
    let toggleExpanded: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leading
            VStack(alignment: .leading, spacing: 6) {
                titleLine
                if case .text(let placeholder) = row.kind, let key = row.key {
                    KeyField(key: key, placeholder: placeholder, alignment: .left)
                        .padding(.vertical, 2)
                }
                if let note { note }
                if let key = row.key, let value = model.folderOverride(key) {
                    FolderNote(key: key, text: FolderNote.text(value, row: row))
                }
            }
            .frame(maxWidth: isFullWidth ? .infinity : nil, alignment: .leading)
            if !isFullWidth { Spacer(minLength: 8) }
            control.frame(height: 16)
        }
        .padding(.vertical, nested ? 8 : 12)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { toggleExpanded() }, isEnabled: hasChevron)
        .background { if ui.isMatch(row.id) { MatchOutline() } }
        .contextMenu {
            if let key = row.key { Button("Reset to Default") { model.reset(key) } }
        }
    }

    /// The title (its tooltip is the key name) and, when the value differs from the default, a small dot.
    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(row.title)
                .font(.system(size: nested ? 12 : 13))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .ifLet(row.key) { $0.help($1) }
            if let key = row.key, model.isModified(key) {
                Circle().fill(.secondary).frame(width: 6, height: 6)
                    .help("Changed from the default")
                    .accessibilityLabel("Changed from the default")
            }
        }
        .frame(minHeight: 16)
    }

    private var isFullWidth: Bool {
        if case .text = row.kind { return true }
        return false
    }

    private var hasChevron: Bool {
        switch row.kind {
        case .group, .flags: true
        default: false
        }
    }

    @ViewBuilder private var leading: some View {
        if let symbol = row.symbol, !nested {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 24, height: 16)
                .padding(.horizontal, 6)
        } else {
            Color.clear.frame(width: nested ? 44 : 36, height: 1)
        }
    }

    /// The error of the last write in red, otherwise the description.
    private var note: Text? {
        if let key = row.key, let error = model.errors[key] {
            return Text(error).font(.system(size: 11)).foregroundStyle(.red)
        }
        guard let description = row.description else { return nil }
        return Text(description).font(.system(size: 11)).foregroundStyle(style.secondaryText)
    }

    @ViewBuilder private var control: some View {
        switch row.kind {
        case .toggle:
            if let key = row.key {
                Toggle("", isOn: Binding(get: { model.value(key) == "yes" },
                                         set: { model.set(key, $0 ? "yes" : "no") }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
        case .choice(let items):
            if let key = row.key { ChoicePicker(key: key, items: items) }
        case .number(let unit, let step):
            if let key = row.key {
                HStack(spacing: 6) {
                    KeyField(key: key, placeholder: nil, alignment: .right, step: step)
                        .frame(width: 72)
                    if let unit {
                        Text(unit).font(.system(size: 13))
                            .foregroundStyle(isEnabled ? style.secondaryText : AnyShapeStyle(.tertiary))
                    }
                }
            }
        case .slider(let range, let marks):
            if let key = row.key { SliderControl(key: key, range: range, marks: marks) }
        case .color(let count):
            if let key = row.key { ColorControl(key: key, count: count, names: row.colorNames) }
        case .icon(let choices):
            if let key = row.key { IconPicker(model: model, key: key, choices: choices) }
        case .text, .custom:
            EmptyView()
        case .button(let title, let action):
            Button(title) { action() }
        case .group, .flags:
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .padding(.trailing, 6)
        }
    }
}

/// One item of an open `.flags` row: a nested row with a switch that adds or removes its word.
struct FlagItemView: View {
    @Environment(SettingsUIState.self) private var ui
    @Environment(SettingsModel.self) private var model
    @Environment(\.isEnabled) private var isEnabled
    let key: String
    let word: String
    let title: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 44, height: 1)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(minHeight: 16)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { words.contains(word) }, set: { set($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .frame(height: 16)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 8)
        .background { if ui.queryMatches(title) { MatchOutline() } }
    }

    private var words: [String] {
        model.value(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func set(_ on: Bool) {
        var list = words.filter { $0 != word }
        if on { list.append(word) }
        model.set(key, list.joined(separator: ","))
    }
}

/// A pop-up of the row's words; a value outside the list is shown as its own item.
struct ChoicePicker: View {
    @Environment(SettingsModel.self) private var model
    let key: String
    let items: [(word: String, title: String)]

    var body: some View {
        let value = model.value(key)
        Picker("", selection: Binding(get: { model.value(key) }, set: { model.set(key, $0) })) {
            ForEach(items, id: \.word) { Text($0.title).tag($0.word) }
            if !items.contains(where: { $0.word == value }) { Text(value).tag(value) }
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
    }
}

/// A slider over the key's number and the name of the nearest mark. The knob moves at once; the value is written
/// after a pause in the drag (`Debouncer`) and at the end of it. Text that is not a number puts the knob at the
/// lower end without a write.
struct SliderControl: View {
    /// Quiet time before a dragged value is written.
    static let pause: TimeInterval = 0.25

    @Environment(SettingsModel.self) private var model
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.settingsStyle) private var style
    let key: String
    let range: ClosedRange<Double>
    let marks: [(value: Double, title: String)]
    /// The knob's value while a drag is not yet written.
    @State private var dragged: Double?
    @State private var debouncer = Debouncer<Double>(delay: SliderControl.pause)

    var body: some View {
        let value = dragged ?? stored
        HStack(spacing: 8) {
            Slider(value: Binding(get: { value }, set: change), in: range) { editing in
                if !editing { debouncer.flush() }
            }
            .labelsHidden().controlSize(.small).frame(width: 120)
            Text(SettingsRow.nearestMark(value, in: marks))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(isEnabled ? style.secondaryText : AnyShapeStyle(.tertiary))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .onDisappear { debouncer.flush() }
    }

    private var stored: Double {
        Double(SettingsModel.normalizedNumber(model.value(key))).map { min(max($0, range.lowerBound), range.upperBound) }
            ?? range.lowerBound
    }

    private func change(_ value: Double) {
        dragged = value
        let model = model, key = key
        let box: State<Double?> = _dragged
        debouncer.submit(value) { value in
            let text = SettingsRow.sliderText(value)
            if text != model.value(key) {
                model.cancelEditing(key)
                model.set(key, text)
            }
            box.wrappedValue = nil
        }
    }
}

/// `count` colour wells over the key's `#rrggbb[,#rrggbb]` value, and the value as an editable text. A well
/// writes after a pause in its changes (`ColorWell`); a part the text cannot be read as shows a neutral grey,
/// and nothing is written or flagged until the user changes a well.
struct ColorControl: View {
    @Environment(SettingsModel.self) private var model
    let key: String
    let count: Int
    /// Value words and the colours they stand for (`SettingsRow.colorNames`).
    let names: [String: String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { ColorWell(key: key, index: $0, count: count, names: names) }
            KeyField(key: key, placeholder: nil, alignment: .left)
                .frame(width: count > 1 ? 150 : 84)
        }
    }
}

/// What one colour well shows: the colour being dragged while a change waits for its commit, otherwise the
/// stored one (so a typed value, Reset to Default, an outside edit or a rejected write show up in the well).
struct WellState: Equatable {
    private(set) var local: Color?

    /// The well was changed by the user.
    mutating func edit(_ color: Color) { local = color }
    /// The change was written (or refused): the store is the truth again.
    mutating func committed() { local = nil }
    /// The store changed: follows it unless a change is waiting for its commit.
    mutating func storeChanged(hasPending: Bool) { if !hasPending { local = nil } }
    /// The colour of part `index` of the key's `text` unless a change is pending.
    func displayed(text: String, index: Int) -> Color { local ?? ColorText.well(text, index: index) }
}

/// One colour well. The well's colour is kept locally while it is dragged, so the picker does not snap back;
/// the model gets it after `pause` without a change (and when the well goes away), then the well follows the
/// store again.
struct ColorWell: View {
    /// Quiet time before a colour is written.
    static let pause: TimeInterval = 0.25

    @Environment(SettingsModel.self) private var model
    let key: String
    let index: Int
    let count: Int
    let names: [String: String]
    @State private var state = WellState()
    @State private var debouncer = Debouncer<Color>(delay: ColorWell.pause)

    var body: some View {
        let text = ColorText.resolved(model.value(key), names: names)
        ColorPicker("", selection: Binding(get: { state.displayed(text: text, index: index) }, set: change),
                    supportsOpacity: false)
            .labelsHidden()
            .onChange(of: text) { state.storeChanged(hasPending: debouncer.pending != nil) }
            .onDisappear { debouncer.flush() }
    }

    private func change(_ color: Color) {
        state.edit(color)
        let model = model, key = key, index = index, count = count, names = names
        let box: State<WellState> = _state
        debouncer.submit(color) { color in
            Self.commit(color, model: model, key: key, index: index, count: count, names: names)
            var current = box.wrappedValue
            current.committed()
            box.wrappedValue = current
        }
    }

    /// Writes the well's colour into the key's text (the other parts as they stand now; a named value as the
    /// colours it names).
    @MainActor static func commit(_ color: Color, model: SettingsModel, key: String, index: Int, count: Int,
                                  names: [String: String] = [:]) {
        let current = ColorText.resolved(model.value(key), names: names)
        let text = ColorText.updating(current, index: index, to: color, count: count)
        guard text != current else { return }
        // A rejected text draft must not linger beside the well's write.
        model.cancelEditing(key)
        model.set(key, text)
    }
}

/// A pop-up of icon names with their pictures (see `IconMenu`).
struct IconPicker: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    /// Passed in (not read from the environment): the coordinator's copy of this struct must have it.
    let model: SettingsModel
    let key: String
    let choices: @MainActor @Sendable () -> [(word: String, image: NSImage?)]

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .systemFont(ofSize: 13)
        popup.menu?.delegate = context.coordinator
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.picked(_:))
        context.coordinator.popup = popup
        // The choices are read here, once per appearance, and again each time the menu opens.
        context.coordinator.reload(model.value(key))
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        popup.isEnabled = isEnabled
        coordinator.select(model.value(key))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: IconPicker
        weak var popup: NSPopUpButton?
        /// The last read choices (with their original pictures).
        private var items: [(word: String, image: NSImage?)] = []
        init(parent: IconPicker) { self.parent = parent }

        /// Reads the choices and rebuilds the menu for `value`.
        func reload(_ value: String) {
            items = parent.choices()
            rebuild(value)
        }

        /// The menu items of the last read choices.
        private func rebuild(_ value: String) {
            guard let popup else { return }
            let menu = popup.menu
            menu?.removeAllItems()
            for item in IconMenu.menuItems(items, value: value) { menu?.addItem(item) }
            select(value)
        }

        /// Selects `value` (adding its item when the menu has none); the closed button shows a 16 pt picture.
        func select(_ value: String) {
            guard let popup, let menu = popup.menu else { return }
            if !menu.items.contains(where: { $0.representedObject as? String == value }) { rebuild(value); return }
            for item in menu.items {
                let word = item.representedObject as? String
                let source = items.first { $0.word == word }?.image
                item.image = IconMenu.menuImage(source, side: word == value ? 16 : IconMenu.side)
            }
            if let item = menu.items.first(where: { $0.representedObject as? String == value }) {
                popup.select(item)
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            // About to open: fresh choices, every item at full size.
            items = parent.choices()
            let value = parent.model.value(parent.key)
            menu.removeAllItems()
            for item in IconMenu.menuItems(items, value: value) { menu.addItem(item) }
            if let item = menu.items.first(where: { $0.representedObject as? String == value }) {
                popup?.select(item)
            }
        }

        func menuDidClose(_ menu: NSMenu) {
            select(parent.model.value(parent.key))
        }

        @objc func picked(_ sender: NSPopUpButton) {
            guard let word = sender.selectedItem?.representedObject as? String else { return }
            parent.model.set(parent.key, word)
            select(parent.model.value(parent.key))
        }
    }
}

enum IconMenu {
    /// Picture size in a menu item.
    static let side: CGFloat = 32

    /// `image` fitted into a transparent `side` × `side` pt square (not a template).
    static func menuImage(_ image: NSImage?, side: CGFloat = IconMenu.side) -> NSImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(side / image.size.width, side / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let result = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            image.draw(in: NSRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        result.isTemplate = false
        return result
    }

    /// One menu item per choice: the word as title (a file path by its file name, the path as tooltip) and as
    /// represented object, its picture at 32 × 32 pt; a `value` outside the choices is appended as an item of its own.
    @MainActor static func menuItems(_ choices: [(word: String, image: NSImage?)], value: String) -> [NSMenuItem] {
        var words = choices
        if !words.contains(where: { $0.word == value }) { words.append((value, nil)) }
        return words.map { choice in
            let isPath = choice.word.contains("/")
            let title = isPath ? (choice.word as NSString).lastPathComponent : choice.word
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if isPath { item.toolTip = choice.word }
            item.representedObject = choice.word
            item.image = menuImage(choice.image)
            return item
        }
    }
}

/// Under a row whose key the current folder sets for itself: «This folder: <value>» and «Use Default», which drops
/// the folder's value (the file's value applies there again).
struct FolderNote: View {
    @Environment(SettingsModel.self) private var model
    @Environment(\.settingsStyle) private var style
    let key: String
    /// The folder's value as the row names it.
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Label("This folder: \(text)", systemImage: "folder")
                .font(.system(size: 11))
                .foregroundStyle(style.secondaryText)
                .help("The folder of the photo on screen has its own value; the setting above applies elsewhere")
            Button("Use Default") { model.clearFolderOverride(key) }
                .controlSize(.small)
                .help("Drop this folder's own value")
        }
    }

    /// The value as the row shows it: a pop-up's item title, On / Off for a switch, otherwise as written.
    static func text(_ value: String, row: SettingsRow) -> String {
        switch row.kind {
        case .choice(let items): items.first { $0.word == value }?.title ?? value
        case .toggle: value == "yes" ? "On" : value == "no" ? "Off" : value
        default: value
        }
    }
}

/// The search outline of a matching row.
struct MatchOutline: View {
    /// The tint inside the outline; off for a large custom view (a table), which it would wash out.
    var filled = true

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(filled ? 0.18 : 0))
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .padding(2)
    }
}

/// A text or number field for `key` over the model's draft (see `SettingsTextField`).
struct KeyField: View {
    @Environment(SettingsModel.self) private var model
    let key: String
    let placeholder: String?
    let alignment: NSTextAlignment
    var step: Double?

    var body: some View {
        SettingsTextField(model: model, key: key, text: model.draft(key) ?? model.value(key),
                          hasDraft: model.draft(key) != nil, invalid: model.errors[key] != nil,
                          placeholder: placeholder, alignment: alignment, step: step)
    }
}

/// Writes on Enter or focus loss; Esc returns the stored value; while it is being edited, an outside change
/// of the key does not replace the typed text. With a `step`, ↑/↓ add or subtract it (⇧ ten times).
struct SettingsTextField: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let model: SettingsModel
    let key: String
    /// The draft, or the value when there is none.
    let text: String
    let hasDraft: Bool
    let invalid: Bool
    let placeholder: String?
    let alignment: NSTextAlignment
    let step: Double?

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        // A field being edited keeps its text; otherwise it shows the draft (a rejected one) or the value.
        let editing = field.currentEditor() != nil
        if !(editing && hasDraft), field.stringValue != text { field.stringValue = text }
        field.layer?.borderColor = invalid ? NSColor.systemRed.cgColor : nil
        field.layer?.borderWidth = invalid ? 1.5 : 0
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsTextField
        init(parent: SettingsTextField) { self.parent = parent }

        private var model: SettingsModel { parent.model }
        private var key: String { parent.key }

        func controlTextDidBeginEditing(_ note: Notification) {
            model.beginEditing(key)
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            model.updateDraft(key, field.stringValue)
        }

        func controlTextDidEndEditing(_ note: Notification) {
            model.commit(key)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                model.commit(key)
                show(model.draft(key) ?? model.value(key), in: textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                model.cancelEditing(key)
                show(model.value(key), in: textView)
                return true
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveUpAndModifySelection(_:)),
                 #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveDownAndModifySelection(_:)):
                guard let step = parent.step else { return false }
                let up = selector == #selector(NSResponder.moveUp(_:))
                    || selector == #selector(NSResponder.moveUpAndModifySelection(_:))
                let shift = selector == #selector(NSResponder.moveUpAndModifySelection(_:))
                    || selector == #selector(NSResponder.moveDownAndModifySelection(_:))
                    || NSEvent.modifierFlags.contains(.shift)
                model.beginEditing(key)
                model.step(key, by: (up ? step : -step) * (shift ? 10 : 1))
                show(model.draft(key) ?? model.value(key), in: textView)
                return true
            default:
                return false
            }
        }

        private func show(_ text: String, in textView: NSTextView) {
            if textView.string != text { textView.string = text }
            textView.selectAll(nil)
        }
    }
}

private extension View {
    /// `transform` applied when `value` is non-nil.
    @ViewBuilder func ifLet<T>(_ value: T?, _ transform: (Self, T) -> some View) -> some View {
        if let value { transform(self, value) } else { self }
    }
}
