import AppKit
import SwiftUI

/// The state of the binding sheet: the input (a recorded key, or a button and how it is pressed), the action and its
/// step. An edited row keeps its input; the sheet changes what it does.
public struct KeyBindingDraft: Identifiable, Equatable {
    public let id = UUID()
    public let isMouse: Bool
    /// The input of the row being edited; nil for a new binding.
    public let editing: String?
    /// The input as the source writes it: a recorded key, or a press kind's id.
    public var input: String?
    /// Why the last key press was not recorded.
    public var refusal: String?
    /// The button pop-up's item (mouse).
    public var button: String?
    public var actionID: String?
    /// The step field, as typed (a comma decimal is read with a dot).
    public var stepText = "0.05"

    /// A new binding.
    public init(isMouse: Bool) {
        self.isMouse = isMouse
        editing = nil
    }

    /// The sheet over an existing row: its input, action and step; for a button, the button whose press kinds hold it.
    @MainActor public init(editing row: KeyBindingRowModel, source: KeyBindingSource) {
        isMouse = row.isMouse
        editing = row.id
        input = row.id
        actionID = row.actionID
        if let step = row.step { stepText = Self.text(step) }
        if row.isMouse {
            button = source.mouseButtons().first { b in source.pressKinds(for: b.id).contains { $0.id == row.id } }?.id
        }
    }

    /// «Replaces: <action>» when the input does something now; nothing for the row being edited.
    @MainActor public func conflict(in source: KeyBindingSource) -> String? {
        guard let input, input != editing, let action = source.conflict(input: input) else { return nil }
        return "Replaces: \(action)"
    }

    @MainActor public func takesStep(in source: KeyBindingSource) -> Bool {
        guard let actionID else { return false }
        return source.actionGroups().contains { $0.actions.contains { $0.id == actionID && $0.takesStep } }
    }

    /// The step of an action that takes one, when the field holds one its `stepRule` accepts; nil otherwise.
    @MainActor public func step(in source: KeyBindingSource) -> Double? {
        guard takesStep(in: source), let actionID, let step = Self.number(stepText),
              source.stepRule(for: actionID).accepts(step) else { return nil }
        return step
    }

    /// Picks the action; one that takes a step gets its rule's default unless the field already holds a step it takes.
    @MainActor public mutating func choose(actionID: String?, in source: KeyBindingSource) {
        self.actionID = actionID
        guard let actionID, takesStep(in: source) else { return }
        let rule = source.stepRule(for: actionID)
        if !(Self.number(stepText).map(rule.accepts) ?? false) { stepText = Self.text(rule.defaultValue) }
    }

    /// The field's text as a number (a comma decimal is read with a dot).
    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// An input, an action, and a good step when the action takes one.
    @MainActor public func canSave(in source: KeyBindingSource) -> Bool {
        input != nil && actionID != nil && (!takesStep(in: source) || step(in: source) != nil)
    }

    /// Whether OK would make `row` do something else than it does (another action or step).
    @MainActor public func changes(_ row: KeyBindingRowModel, in source: KeyBindingSource) -> Bool {
        input != row.id || actionID != row.actionID || step(in: source) != row.step
    }

    @MainActor public func save(to source: KeyBindingSource) throws {
        guard canSave(in: source), let input, let actionID else { return }
        try source.bind(input: input, action: actionID, step: step(in: source))
    }

    /// A key press in the recorder: its input, or the reason it is refused (the last good input stays). True when the
    /// press was recorded: the recorder then gives up the focus.
    @discardableResult
    @MainActor public mutating func record(_ event: NSEvent, in source: KeyBindingSource) -> Bool {
        switch source.keyToken(for: event) {
        case .success(let token):
            input = token
            refusal = nil
            return true
        case .failure(let refused):
            refusal = refused.text
            return false
        }
    }

    /// Another button: the same press kind on it when it takes that, else its first kind that is enabled.
    @MainActor public mutating func select(button new: String, in source: KeyBindingSource) {
        let old = button.map { source.pressKinds(for: $0) } ?? []
        let index = old.firstIndex { $0.id == input }
        let kinds = source.pressKinds(for: new)
        button = new
        if let index, kinds.indices.contains(index), kinds[index].enabled {
            input = kinds[index].id
        } else {
            input = kinds.first(where: \.enabled)?.id
        }
    }

    /// `0.05`, `1`, `-0.25`.
    static func text(_ step: Double) -> String {
        step == step.rounded() && abs(step) < 1e9 ? String(Int(step)) : String(step)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.input == b.input && a.refusal == b.refusal && a.button == b.button
            && a.actionID == b.actionID && a.stepText == b.stepText
    }
}

/// The sheet of «+» and a double-click: a key recorder, or button and press kind pop-ups; the action by
/// group; a step for the actions that take one; «Replaces: …» when the input is taken. `done` gets the draft on OK,
/// nil on Cancel.
struct KeyBindingSheet: View {
    let source: KeyBindingSource
    @State var draft: KeyBindingDraft
    let done: (KeyBindingDraft?) -> Void

    init(source: KeyBindingSource, draft: KeyBindingDraft, done: @escaping (KeyBindingDraft?) -> Void) {
        self.source = source
        _draft = State(initialValue: draft)
        self.done = done
    }

    private var title: String {
        if draft.editing != nil { return "Change Binding" }
        return draft.isMouse ? "Bind a Mouse Button" : "Bind a Key"
    }

    /// The sheet's width; the content fits in it less the padding.
    static let width: CGFloat = 440
    /// The action pop-up at most: the sheet's inner width less the label column and the gap.
    static let actionWidth: CGFloat = width - 40 - 80

    var body: some View {
        content
            .padding(20)
            .frame(width: Self.width)
    }

    /// Everything inside the padding, at its own size (a test measures it).
    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 13, weight: .bold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                // Centred: the recorder (an NSView) has no text baseline to align the label with.
                GridRow(alignment: .center) {
                    Text(draft.isMouse ? "Button:" : "Key:").gridColumnAlignment(.trailing)
                    if draft.isMouse { mouseInput } else { keyInput }
                }
                if let note {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        note.font(.system(size: 11))
                    }
                }
                GridRow {
                    Text("Action:")
                    actionPicker
                }
                if draft.takesStep(in: source) {
                    GridRow {
                        Text("Step:")
                        HStack(spacing: 8) {
                            TextField(KeyBindingDraft.text(stepRule.defaultValue), text: $draft.stepText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                            Text(stepRule.hint)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { done(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave(in: source))
            }
        }
    }

    /// The chosen action's step rule (the sheet asks only while it takes a step).
    private var stepRule: KeyBindingStep { draft.actionID.map(source.stepRule) ?? .standard }

    /// The refusal of the last press in red, otherwise what the input does now.
    private var note: Text? {
        if let refusal = draft.refusal { return Text(refusal).foregroundStyle(.red) }
        return draft.conflict(in: source).map { Text($0).foregroundStyle(.secondary) }
    }

    @ViewBuilder private var keyInput: some View {
        if draft.editing != nil {
            Text(draft.input ?? "").font(.system(size: 13, design: .monospaced))
        } else {
            KeyRecorder(text: draft.input ?? "", placeholder: "Press a key") { draft.record($0, in: source) }
                .frame(width: 220, height: 24)
        }
    }

    @ViewBuilder private var mouseInput: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { draft.button }, set: { if let b = $0 { draft.select(button: b, in: source) } })) {
                if draft.button == nil { Text("Choose…").tag(String?.none) }
                ForEach(source.mouseButtons(), id: \.id) { Text($0.title).tag(Optional($0.id)) }
            }
            .labelsHidden().fixedSize()
            Picker("", selection: $draft.input) {
                if draft.input == nil { Text("Choose…").tag(String?.none) }
                ForEach(draft.button.map { source.pressKinds(for: $0) } ?? [], id: \.id) { kind in
                    Text(kind.title).tag(Optional(kind.id)).disabled(!kind.enabled)
                }
            }
            .labelsHidden().fixedSize()
        }
        .disabled(draft.editing != nil)
    }

    private var actionPicker: some View {
        Picker("", selection: Binding(get: { draft.actionID }, set: { draft.choose(actionID: $0, in: source) })) {
            if draft.actionID == nil { Text("Choose…").tag(String?.none) }
            ForEach(source.actionGroups(), id: \.group) { group in
                Section(group.group) {
                    ForEach(group.actions, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                }
            }
        }
        // Not its own size: a pop-up is as wide as its longest item, and an action title can be wider than the sheet
        // (the edges were clipped). The chosen title is cut short instead; the menu still shows every title whole.
        .labelsHidden().frame(maxWidth: Self.actionWidth, alignment: .leading)
    }
}

/// A field that records one key press while it has the focus. A local event monitor takes the presses first, so Space
/// and ⌘ chords are recorded (or refused) instead of reaching the menus. It is focused when it appears, and there Esc
/// and Return still go to Cancel and OK; after a click into it they are recorded too. A recorded press ends the
/// recording (the field gives up the focus, so Return is OK again); a click records again. Tab always moves on.
struct KeyRecorder: NSViewRepresentable {
    let text: String
    let placeholder: String
    /// Records the press; true when it was taken.
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.placeholder = placeholder
        return view
    }

    func updateNSView(_ view: KeyRecorderView, context: Context) {
        view.text = text
        view.onKey = onKey
    }
}

final class KeyRecorderView: NSView {
    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }
    var placeholder = ""
    var onKey: ((NSEvent) -> Bool)?
    private var monitor: Any?
    private var focused = false { didSet { needsDisplay = true } }
    /// The focus came from a click (not from the sheet opening): every key records, Esc and Return included.
    private var clicked = false

    enum Decision: Equatable { case record, pass }

    /// What a press does in the focused recorder: Tab moves on; until the user clicked into the field, Esc, Return
    /// and Enter go on to the sheet's Cancel and OK; everything else is recorded.
    static func decision(keyCode: UInt16, clicked: Bool) -> Decision {
        let tab: UInt16 = 48, escape: UInt16 = 53, ret: UInt16 = 36, enter: UInt16 = 76
        if keyCode == tab { return .pass }
        if !clicked, [escape, ret, enter].contains(keyCode) { return .pass }
        return .record
    }

    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { removeMonitor(); return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        installMonitor()
        focused = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        removeMonitor()
        focused = false
        clicked = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        clicked = true
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.window?.firstResponder === self,
                  Self.decision(keyCode: event.keyCode, clicked: self.clicked) == .record else { return event }
            if self.onKey?(event) == true { self.window?.makeFirstResponder(nil) }
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.stroke()
        let shown = text.isEmpty ? (focused ? placeholder : "Click to record") : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: text.isEmpty ? NSFont.systemFont(ofSize: 13) : NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: text.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor,
        ]
        let string = NSAttributedString(string: shown, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
