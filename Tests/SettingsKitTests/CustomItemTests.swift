import Testing
import SwiftUI
import AppKit
@testable import SettingsKit

@MainActor
struct CustomItemTests {
    private func gray(_ white: Double) -> Color { Color(.sRGB, red: white, green: white, blue: white, opacity: 1) }

    @Test func colorHexRoundTrips() {
        #expect(ColorText.hex(gray(0.2)) == "#333333")
        #expect(ColorText.hex(Color(.sRGB, red: 1, green: 0, blue: 0.5, opacity: 1)) == "#ff0080")
        let short = ColorText.colors("#333")
        #expect(short?.count == 1)
        #expect(short.map { ColorText.hex($0[0]) } == "#333333")
        let long = ColorText.colors(" #AbCdEf ")
        #expect(long.map { ColorText.hex($0[0]) } == "#abcdef")
        let two = ColorText.colors("#333333, #666")
        #expect(two?.map(ColorText.hex) == ["#333333", "#666666"])
    }

    @Test func unreadableColourTextIsNil() {
        for text in ["", "red", "#12", "#12345", "#1234567", "#gggggg", "333333", "#333333,", "#333333,blue"] {
            #expect(ColorText.colors(text) == nil, "\(text)")
        }
    }

    @Test func twoColoursWriteList() {
        #expect(ColorText.text([gray(0.2), gray(0.4)]) == "#333333,#666666")
        // One picker changed: the other part is kept as it stands.
        #expect(ColorText.updating("#333333,#666666", index: 1, to: gray(0.6), count: 2) == "#333333,#999999")
        #expect(ColorText.updating("#333333,#666666", index: 0, to: gray(0.6), count: 2) == "#999999,#666666")
        // Unreadable or missing parts stay as typed / become neutral grey.
        #expect(ColorText.updating("#333333,oops", index: 0, to: gray(0.6), count: 2) == "#999999,oops")
        #expect(ColorText.updating("", index: 1, to: gray(0.2), count: 2) == "#808080,#333333")
        #expect(ColorText.updating("#111", index: 0, to: gray(0.2), count: 1) == "#333333")

        let store = MemoryStore(values: ["checker-colors": "#333333,#666666"])
        let model = SettingsModel(store: store)
        let row = SettingsRow.color("checker-colors", "Checker colours", count: 2)
        model.register([page([row])])
        guard case .color(let count) = row.kind else { Issue.record("not a colour row"); return }
        #expect(count == 2)
        model.set("checker-colors", ColorText.updating(model.value("checker-colors"), index: 1, to: gray(0.6), count: count))
        #expect(store.values["checker-colors"] == "#333333,#999999")
    }

    @Test func iconChoiceWritesWord() {
        let store = MemoryStore(values: ["app-icon": "owl"])
        let model = SettingsModel(store: store)
        let row = SettingsRow.icon("app-icon", "App icon", choices: { [("owl", nil), ("horse", NSImage(size: NSSize(width: 64, height: 64)))] })
        model.register([page([row])])
        guard case .icon(let choices) = row.kind else { Issue.record("not an icon row"); return }
        #expect(choices().map(\.word) == ["owl", "horse"])
        model.set("app-icon", choices()[1].word)
        #expect(store.values["app-icon"] == "horse")
        #expect(model.value("app-icon") == "horse")
    }

    @Test func menuIconsAreScaledTo32Points() {
        let big = NSImage(size: NSSize(width: 512, height: 256))
        let scaled = IconMenu.menuImage(big)
        #expect(scaled?.size == NSSize(width: 32, height: 32))
        #expect(IconMenu.menuImage(nil) == nil)
    }
}

/// A clock the test advances by hand.
@MainActor
private final class FakeClock {
    private var timers: [(id: Int, due: TimeInterval, action: @MainActor () -> Void)] = []
    private var next = 0
    private(set) var now: TimeInterval = 0
    var scheduled = 0

    var schedule: Debouncer<String>.Schedule {
        { [self] delay, action in
            let id = next
            next += 1
            scheduled += 1
            timers.append((id, now + delay, action))
            return { [self] in timers.removeAll { $0.id == id } }
        }
    }

    func advance(_ seconds: TimeInterval) {
        now += seconds
        while let i = timers.firstIndex(where: { $0.due <= now }) {
            let timer = timers.remove(at: i)
            timer.action()
        }
    }
}

@MainActor
struct DebouncerTests {
    @Test func burstCommitsOnlyTheLastValueAfterThePause() {
        let clock = FakeClock()
        let debouncer = Debouncer<String>(delay: 0.25, schedule: clock.schedule)
        var committed: [String] = []
        for value in ["a", "b", "c"] {
            debouncer.submit(value) { committed.append($0) }
            clock.advance(0.1)
        }
        #expect(committed.isEmpty)
        #expect(debouncer.pending == "c")
        clock.advance(0.2)
        #expect(committed == ["c"])
        #expect(debouncer.pending == nil)
        clock.advance(1)
        #expect(committed == ["c"])
    }

    @Test func flushCommitsAtOnceAndOnlyOnce() {
        let clock = FakeClock()
        let debouncer = Debouncer<String>(delay: 0.25, schedule: clock.schedule)
        var committed: [String] = []
        debouncer.flush()
        #expect(committed.isEmpty)
        debouncer.submit("x") { committed.append($0) }
        debouncer.flush()
        #expect(committed == ["x"])
        clock.advance(1)
        #expect(committed == ["x"])
    }

    @Test func cancelDropsThePendingValue() {
        let clock = FakeClock()
        let debouncer = Debouncer<String>(delay: 0.25, schedule: clock.schedule)
        var committed: [String] = []
        debouncer.submit("x") { committed.append($0) }
        debouncer.cancel()
        debouncer.flush()
        clock.advance(1)
        #expect(committed.isEmpty)
        #expect(debouncer.pending == nil)
    }

    @Test func realClockCommitsAfterThePause() async throws {
        let debouncer = Debouncer<String>(delay: 0.05)
        var committed: [String] = []
        debouncer.submit("a") { committed.append($0) }
        debouncer.submit("b") { committed.append($0) }
        // Wait for the commit rather than a fixed time: a loaded CI machine can hold the main actor for a while.
        let deadline = ContinuousClock.now + .seconds(5)
        while committed.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(committed == ["b"])
    }
}

@MainActor
struct IconMenuTests {
    @Test func menuItemsCarryWordAnd32ptPicture() {
        let big = NSImage(size: NSSize(width: 512, height: 512))
        let items = IconMenu.menuItems([("owl", big), ("plain", nil)], value: "owl")
        #expect(items.map(\.title) == ["owl", "plain"])
        #expect(items.map { $0.representedObject as? String } == ["owl", "plain"])
        #expect(items[0].image?.size == NSSize(width: 32, height: 32))
        #expect(items[1].image == nil)
    }

    @Test func unknownValueIsAnExtraItem() {
        let items = IconMenu.menuItems([("owl", nil)], value: "dragon")
        #expect(items.map(\.title) == ["owl", "dragon"])
        #expect(items[1].representedObject as? String == "dragon")
    }

    /// A file path is titled by its file name (the full path is the tooltip), so the closed pop-up stays narrow.
    @Test func pathValueIsTitledByItsFileName() {
        let items = IconMenu.menuItems([("owl", nil)], value: "/Users/me/icons/gz1c.png")
        #expect(items.map(\.title) == ["owl", "gz1c.png"])
        #expect(items[1].representedObject as? String == "/Users/me/icons/gz1c.png")
        #expect(items[1].toolTip == "/Users/me/icons/gz1c.png")
        #expect(IconMenu.menuItems([("~/x.png", nil)], value: "owl")[0].title == "x.png")
    }
}

@MainActor
struct WellStateTests {
    private func gray(_ white: Double) -> Color { Color(.sRGB, red: white, green: white, blue: white, opacity: 1) }
    private func hex(_ color: Color) -> String { ColorText.hex(color) }

    @Test func wellFollowsStoreAfterEditCommitAndOutsideChange() {
        let store = MemoryStore(values: ["c": "#333333"])
        let model = SettingsModel(store: store)
        model.register([page([.color("c", "C")])])
        var state = WellState()
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#333333")

        // Dragging: the well shows the dragged colour although the store still has the old one.
        state.edit(gray(0.6))
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#999999")
        // An outside change while the change waits does not take the well away.
        state.storeChanged(hasPending: true)
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#999999")

        // The commit writes and hands the well back to the store.
        ColorWell.commit(gray(0.6), model: model, key: "c", index: 0, count: 1)
        state.committed()
        #expect(store.values["c"] == "#999999")
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#999999")

        // Typed value, Reset to Default, outside edit: the well shows the new stored colour.
        store.changeExternally(["c": "#112233"])
        state.storeChanged(hasPending: false)
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#112233")
        model.set("c", "#ff0000")
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#ff0000")
    }

    @Test func storeChangeWithNothingPendingDropsTheLocalColour() {
        var state = WellState()
        state.edit(gray(0.6))
        state.storeChanged(hasPending: false)
        #expect(state.local == nil)
        #expect(hex(state.displayed(text: "#112233", index: 0)) == "#112233")
    }

    @Test func rejectedCommitShowsTheStoredColour() {
        let store = MemoryStore(values: ["c": "#333333"], validate: { v, _ in v == "#999999" ? "Not allowed" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.color("c", "C")])])
        var state = WellState()
        state.edit(gray(0.6))
        ColorWell.commit(gray(0.6), model: model, key: "c", index: 0, count: 1)
        state.committed()
        #expect(model.errors["c"] == "Not allowed")
        #expect(store.values["c"] == "#333333")
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#333333")
    }

    @Test func secondWellShowsNeutralGreyForMissingPart() {
        #expect(hex(ColorText.well("#333333", index: 1)) == "#808080")
        #expect(hex(ColorText.well("#333333,oops", index: 1)) == "#808080")
        #expect(hex(ColorText.well("#333333,#666", index: 1)) == "#666666")
    }
}
