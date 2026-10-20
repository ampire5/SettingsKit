import AppKit
import SwiftUI
import Testing
@testable import SettingsKit

/// A binding table over a dictionary: input → (action title, action id, source).
@MainActor
class FakeBindingSource: KeyBindingSource {
    var table: [KeyBindingRowModel]
    var bound: [(input: String, action: String, step: Double?)] = []

    init(_ table: [KeyBindingRowModel]) { self.table = table }

    func rows() -> [KeyBindingRowModel] { table }
    func actionGroups() -> [(group: String, actions: [(id: String, title: String, takesStep: Bool)])] {
        [("Zoom", [("fit", "Fit to window", false), ("fill", "Fill the window", false)]),
         ("Colour", [("add vibrance-amount", "Vibrance amount", true)])]
    }
    func mouseButtons() -> [(id: String, title: String)] { [("MBTN_MID", "Middle"), ("MX_PANEL", "Panel")] }
    func pressKinds(for button: String) -> [(id: String, title: String, enabled: Bool)] {
        [(button, "Tap", true), (button + "-long", "Long press", true), ("MBTN_RIGHT+" + button, "With right", button == "MBTN_MID")]
    }
    func keyToken(for event: NSEvent) -> Result<String, KeyBindingRefusal> { .failure(KeyBindingRefusal("no keys")) }
    func conflict(input: String) -> String? {
        table.first { $0.id == input && $0.actionID != nil }?.action
    }
    func bind(input: String, action: String, step: Double?) throws { bound.append((input, action, step)) }
    func remove(rowID: String) throws {}
    func restoreBuiltIn(rowID: String) throws {}
}

@MainActor
struct KeyBindingTableTests {
    private let rows = [
        KeyBindingRowModel(id: "f", input: "F", action: "Fit to window", source: "built-in", isMouse: false,
                           actionID: "fit"),
        KeyBindingRowModel(id: "v", input: "V", action: "Vibrance on/off (this folder)", source: "input.conf",
                           isMouse: false, actionID: "toggle-vibrance", canRestore: true),
        KeyBindingRowModel(id: "MX_GESTURE+WHEEL", input: "Gesture button + wheel", action: "Vibrance amount ±0.05",
                           source: "built-in", isMouse: true, actionID: "add vibrance-amount", step: 0.05),
        KeyBindingRowModel(id: "MBTN_MID", input: "Middle", action: "Unbound", source: "off", isMouse: true,
                           canRestore: true, canRemove: false),
    ]

    /// A read-only row (a menu's shortcut) opens no sheet and cannot be removed.
    @Test func readOnlyRowsAreNotEdited() {
        let menu = KeyBindingRowModel(id: "menu ⌘T", input: "⌘T", action: "New Tab", source: "menu", isMouse: false,
                                      canRemove: false, isEditable: false)
        let all = rows + [menu]
        #expect(KeyBindingTable.editTarget(all, ids: ["f"]) == "f")
        #expect(KeyBindingTable.editTarget(all, ids: ["menu ⌘T"]) == nil)
        #expect(KeyBindingTable.editTarget(all, ids: ["f", "v"]) == nil)
        #expect(KeyBindingTable.removalTargets(shown: all, selection: ["menu ⌘T"]).isEmpty)
        #expect(rows[0].isEditable)
    }

    @Test func filterNarrowsRows() {
        #expect(KeyBindingTable.filtered(rows, query: "").count == 4)
        #expect(KeyBindingTable.filtered(rows, query: "  ").count == 4)
        // Action titles, case-insensitive.
        #expect(KeyBindingTable.filtered(rows, query: "VIBRANCE").map(\.id) == ["v", "MX_GESTURE+WHEEL"])
        // The input as shown and as input.conf spells it.
        #expect(KeyBindingTable.filtered(rows, query: "gesture").map(\.id) == ["MX_GESTURE+WHEEL"])
        #expect(KeyBindingTable.filtered(rows, query: "MX_GESTURE+W").map(\.id) == ["MX_GESTURE+WHEEL"])
        // The source column.
        #expect(KeyBindingTable.filtered(rows, query: "input.conf").map(\.id) == ["v"])
        #expect(KeyBindingTable.filtered(rows, query: "nothing like it").isEmpty)
    }

    /// The window's search narrows a table only when some of its rows match; otherwise (the page matched by its other
    /// table or a section title) the table keeps every row.
    @Test func windowSearchNarrowsOnlyOnAMatch() {
        #expect(KeyBindingTable.searched(rows, query: "fit").map(\.id) == ["f"])
        #expect(KeyBindingTable.searched(rows, query: "keyboard").count == 4)
        #expect(KeyBindingTable.searched(rows, query: "").count == 4)
    }

    @Test func conflictText() {
        let source = FakeBindingSource(rows)
        var draft = KeyBindingDraft(isMouse: false)
        #expect(draft.conflict(in: source) == nil)
        draft.input = "f"
        #expect(draft.conflict(in: source) == "Replaces: Fit to window")
        // An unbound input replaces nothing.
        draft.input = "MBTN_MID"
        #expect(draft.conflict(in: source) == nil)
        draft.input = "g"
        #expect(draft.conflict(in: source) == nil)
        // The row being edited does not conflict with itself.
        var edit = KeyBindingDraft(editing: rows[0], source: source)
        #expect(edit.input == "f")
        #expect(edit.actionID == "fit")
        #expect(edit.conflict(in: source) == nil)
        #expect(!edit.changes(rows[0], in: source))
        edit.actionID = "fill"
        #expect(edit.conflict(in: source) == nil)
        #expect(edit.changes(rows[0], in: source))
        var add = KeyBindingDraft(editing: rows[2], source: source)
        #expect(!add.changes(rows[2], in: source))
        add.stepText = "0.1"
        #expect(add.changes(rows[2], in: source))
    }

    @Test func draftNeedsInputActionAndStep() {
        let source = FakeBindingSource(rows)
        var draft = KeyBindingDraft(isMouse: false)
        #expect(!draft.canSave(in: source))
        draft.input = "g"
        #expect(!draft.canSave(in: source))
        draft.actionID = "fit"
        #expect(draft.canSave(in: source))
        #expect(draft.step(in: source) == nil)
        draft.actionID = "add vibrance-amount"
        draft.stepText = "0,1"                      // a comma decimal is read as 0.1
        #expect(draft.step(in: source) == 0.1)
        #expect(draft.canSave(in: source))
        for bad in ["0", "1.5", "-2", "x", ""] {
            draft.stepText = bad
            #expect(!draft.canSave(in: source), "\(bad)")
        }
        draft.stepText = "-0.05"                    // a step down
        #expect(draft.canSave(in: source))
        try? draft.save(to: source)
        #expect(source.bound.last?.input == "g")
        #expect(source.bound.last?.action == "add vibrance-amount")
        #expect(source.bound.last?.step == -0.05)
    }

    @Test func mouseDraftPicksAnEnabledKind() {
        let source = FakeBindingSource(rows)
        var draft = KeyBindingDraft(isMouse: true)
        draft.select(button: "MX_PANEL", in: source)
        #expect(draft.input == "MX_PANEL")
        draft.input = "MX_PANEL-long"
        draft.select(button: "MBTN_MID", in: source)
        // The same kind on the new button.
        #expect(draft.input == "MBTN_MID-long")
        draft.input = "MBTN_RIGHT+MBTN_MID"
        draft.select(button: "MX_PANEL", in: source)
        // With right is disabled for the panel: the first enabled kind.
        #expect(draft.input == "MX_PANEL")
        // Editing a mouse row finds its button; an `add` row keeps its step.
        let edit = KeyBindingDraft(editing: rows[3], source: source)
        #expect(edit.button == "MBTN_MID")
        #expect(edit.input == "MBTN_MID")
        let add = KeyBindingDraft(editing: rows[2], source: source)
        #expect(add.stepText == "0.05")
        #expect(add.step(in: source) == 0.05)
    }

    @Test func customRowSearchAsksItsTexts() {
        final class Box: @unchecked Sendable { var texts = ["F", "Fit to window"] }
        let box = Box()
        let row = SettingsRow.custom("Keyboard bindings", searchTexts: { box.texts }) { Text("table") }
        let search = SettingsSearch(pages: [page([row], section: "Keyboard")])
        #expect(search.matches("fit").map(\.rowID) == [row.id])
        // Asked again on every search: the file may have changed.
        box.texts = ["G", "Fill the window"]
        #expect(search.matches("fit").isEmpty)
        #expect(search.matches("fill").map(\.rowID) == [row.id])
        // The row's own title is not searched (it is never shown); the section's is.
        #expect(search.matches("bindings").isEmpty)
        #expect(search.matches("keyboard").map(\.rowID) == [row.id])
        #expect(page([row]).keys.isEmpty)
    }

    /// The filter and the window's search also find a row by its action as the file names it.
    @Test func filterMatchesActionID() {
        #expect(KeyBindingTable.filtered(rows, query: "add vibrance-amount").map(\.id) == ["MX_GESTURE+WHEEL"])
        #expect(KeyBindingTable.searched(rows, query: "toggle-vibrance").map(\.id) == ["v"])
    }

    /// «−» and Delete act on the selected rows the table shows (a filter may hide selected ones), never on an off row.
    @Test func removalTargetsOnlyShownRows() {
        let shown = KeyBindingTable.filtered(rows, query: "vibrance")          // v, MX_GESTURE+WHEEL
        let selection: Set<String> = ["f", "v", "MBTN_MID"]
        #expect(KeyBindingTable.removalTargets(shown: shown, selection: selection).map(\.id) == ["v"])
        #expect(KeyBindingTable.removalTargets(shown: rows, selection: selection).map(\.id) == ["f", "v"])
        #expect(KeyBindingTable.removalTargets(shown: rows, selection: []).isEmpty)
    }

    /// The recorder records once: focused on appear, Esc and Return still reach Cancel and OK; after a click into it
    /// every key records (Esc and Return can be bound); Tab always moves on.
    @Test func recorderPassesEscUntilClicked() {
        let esc: UInt16 = 53, ret: UInt16 = 36, enter: UInt16 = 76, tab: UInt16 = 48, f: UInt16 = 3
        for key in [esc, ret, enter, tab] {
            #expect(KeyRecorderView.decision(keyCode: key, clicked: false) == .pass)
        }
        #expect(KeyRecorderView.decision(keyCode: f, clicked: false) == .record)
        for key in [esc, ret, enter, f] {
            #expect(KeyRecorderView.decision(keyCode: key, clicked: true) == .record)
        }
        #expect(KeyRecorderView.decision(keyCode: tab, clicked: true) == .pass)
    }

    /// A recorded key ends the recording (the recorder gives up the focus, so Return is OK again); a refused one does
    /// not.
    @Test func recordReportsSuccess() {
        final class Recorder: FakeBindingSource {
            var answer: Result<String, KeyBindingRefusal> = .success("g")
            override func keyToken(for event: NSEvent) -> Result<String, KeyBindingRefusal> { answer }
        }
        let source = Recorder(rows)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "g", charactersIgnoringModifiers: "g", isARepeat: false,
                                     keyCode: 5)!
        var draft = KeyBindingDraft(isMouse: false)
        let taken = draft.record(event, in: source)
        #expect(taken)
        #expect(draft.input == "g")
        source.answer = .failure(KeyBindingRefusal("no"))
        let refused = draft.record(event, in: source)
        #expect(!refused)
        #expect(draft.input == "g")
        #expect(draft.refusal == "no")
    }
}

/// An action title far wider than the sheet.
@MainActor
final class LongTitleSource: FakeBindingSource {
    override func actionGroups() -> [(group: String, actions: [(id: String, title: String, takesStep: Bool)])] {
        [("Tabs", [("back", String(repeating: "Back to Recent, Folders or Stash, where it was opened from ", count: 2), false)])]
    }
}

@MainActor
struct KeyBindingSheetTests {
    /// A long action title is cut short in the pop-up; the sheet keeps its width, so nothing is clipped at its edges.
    @Test func longActionTitleKeepsTheSheetWidth() {
        for isMouse in [false, true] {
            var draft = KeyBindingDraft(isMouse: isMouse)
            draft.actionID = "back"
            for d in [draft, KeyBindingDraft(isMouse: isMouse)] {
                let sheet = KeyBindingSheet(source: LongTitleSource([]), draft: d, done: { _ in })
                // The content asked for at the sheet's inner width reports no more than that width.
                let ideal = NSHostingView(rootView: sheet.content.fixedSize())
                #expect(ideal.fittingSize.width <= KeyBindingSheet.width - 40, "mouse: \(isMouse), action: \(d.actionID ?? "none")")
            }
        }
    }
}
