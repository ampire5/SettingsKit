import Testing
import Foundation
@testable import SettingsKit

@MainActor
struct RowExtrasTests {
    @Test func writeFailureIsReported() {
        let store = MemoryStore(values: ["a": "no"], defaults: ["a": "no"])
        store.writeError = DiskFull()
        let model = SettingsModel(store: store)
        #expect(model.writeFailure == nil)
        model.set("a", "yes")
        #expect(model.writeFailure?.key == "a")
        #expect(model.writeFailure?.message == DiskFull().localizedDescription)
        #expect(model.value("a") == "no")
        #expect(store.values["a"] == "no")
        // the sheet is a message, not a row error
        #expect(model.errors["a"] == nil)
        model.clearWriteFailure()
        #expect(model.writeFailure == nil)
    }

    @Test func writeFailureOfAResetIsReported() {
        let store = MemoryStore(values: ["a": "yes"], defaults: ["a": "no"])
        store.writeError = DiskFull()
        let model = SettingsModel(store: store)
        model.reset("a")
        #expect(model.writeFailure?.key == "a")
        #expect(model.value("a") == "yes")
    }

    @Test func resetRemovesTheValue() {
        let store = MemoryStore(values: ["n": "300"], defaults: ["n": "250"],
                                validate: { v, _ in Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N")])])
        model.beginEditing("n")
        model.updateDraft("n", "x")
        model.commit("n")
        #expect(model.errors["n"] != nil)
        model.reset("n")
        #expect(store.values["n"] == nil)
        #expect(model.value("n") == "250")
        #expect(model.errors["n"] == nil)
        #expect(model.draft("n") == nil)
    }

    @Test func resetAtDefaultStillRemovesTheValue() {   // a value written equal to the default stops pinning it
        let store = MemoryStore(values: ["a": "no"], defaults: ["a": "no"])
        let model = SettingsModel(store: store)
        model.reset("a")
        #expect(store.values["a"] == nil)
    }

    @Test func storeThatCannotRemoveWritesTheDefault() {
        final class PlainStore: SettingsStore {
            var values = ["a": "yes"]
            func value(forKey key: String) -> String? { values[key] }
            func defaultValue(forKey key: String) -> String { "no" }
            func validate(_ value: String, forKey key: String) -> String? { nil }
            func setValue(_ value: String, forKey key: String) throws { values[key] = value }
        }
        let store = PlainStore()
        SettingsModel(store: store).reset("a")
        #expect(store.values["a"] == "no")
    }

    @Test func resetPageRemovesOnlyItsChangedKeysAtOnce() {
        let store = MemoryStore(values: ["a": "yes", "b": "no", "c": "9", "x": "yes"],
                                defaults: ["a": "no", "b": "no", "c": "1", "x": "no"])
        let model = SettingsModel(store: store)
        let p = page([.toggle("a", "A"), .toggle("b", "B"), .number("c", "C")])
        model.register([p])
        #expect(model.modifiedKeys(in: p) == ["a", "c"])
        model.resetPage(p)
        #expect(store.removedBatches == [["a", "c"]])
        #expect(store.values == ["b": "no", "x": "yes"])
        #expect(model.modifiedKeys(in: p).isEmpty)
        model.resetPage(p)   // nothing changed: no store call
        #expect(store.removedBatches.count == 1)
    }

    @Test func modifiedFollowsValue() {
        let store = MemoryStore(values: [:], defaults: ["a": "no"])
        let model = SettingsModel(store: store)
        #expect(!model.isModified("a"))
        model.set("a", "yes")
        #expect(model.isModified("a"))
        model.reset("a")
        #expect(!model.isModified("a"))
        store.changeExternally(["a": "yes"])
        #expect(model.isModified("a"))
    }

    @Test func errorClearedByGoodWrite() {
        let store = MemoryStore(values: ["n": "1"], defaults: ["n": "1"],
                                validate: { v, _ in Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.set("n", "x")
        #expect(model.errors["n"] == "Not a valid value")
        model.set("n", "2")
        #expect(model.errors["n"] == nil)
    }

    @Test func cancelEditingDropsDraft() {
        let store = MemoryStore(values: ["n": "1"], defaults: ["n": "1"],
                                validate: { v, _ in Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N")])])
        model.beginEditing("n")
        model.updateDraft("n", "x")
        model.commit("n")
        #expect(model.draft("n") == "x")
        #expect(model.errors["n"] != nil)
        model.cancelEditing("n")
        #expect(model.draft("n") == nil)
        #expect(model.errors["n"] == nil)
        #expect(model.value("n") == "1")
    }

    @Test func searchFindsKeyName() {
        let rows: [SettingsRow] = [
            .number("strip-height", "Height", unit: "pt"),
            .toggle("vibrance", "Vibrance", nested: [.number("vibrance-amount", "Amount")]),
            .toggle("other", "Other"),
        ]
        let search = SettingsSearch(pages: [page(rows, section: "Strip")])
        #expect(search.matches("strip-height").map(\.rowID) == ["strip-height"])
        // a part of a key finds every key containing it
        #expect(search.matches("vibrance").map(\.rowID) == ["vibrance", "vibrance-amount"])
        #expect(search.matches("vibrance-amount").map(\.rowID) == ["vibrance-amount"])
    }

    @Test func failedWriteClearsStaleErrorAndDraft() {
        let store = MemoryStore(values: ["n": "1"], defaults: ["n": "1"],
                                validate: { v, _ in Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N")])])
        model.beginEditing("n")
        model.updateDraft("n", "x")
        model.commit("n")
        #expect(model.errors["n"] != nil)
        #expect(model.draft("n") == "x")
        store.writeError = DiskFull()
        model.updateDraft("n", "5")
        model.commit("n")
        #expect(model.errors["n"] == nil)
        #expect(model.draft("n") == nil)
        #expect(model.value("n") == "1")
        #expect(model.writeFailure?.key == "n")
    }
    @Test func sliderRowBuildsAndNamesNearestMark() {
        let marks: [(value: Double, title: String)] = [(0.5625, "9:16"), (0.75, "3:4"), (1, "1:1"), (4.0 / 3, "4:3"),
                                                       (1.5, "3:2")]
        let row = SettingsRow.slider("strip-cell-max", "Widest thumbnail", range: 0.5625...1.5, marks: marks)
        guard case .slider(let range, let built) = row.kind else {
            Issue.record("not a slider: \(row.kind)")
            return
        }
        #expect(range == 0.5625...1.5)
        #expect(built.map(\.value) == marks.map(\.value))
        #expect(built.map(\.title) == marks.map(\.title))
        #expect(SettingsRow.nearestMark(0.58, in: marks) == "9:16")
        #expect(SettingsRow.nearestMark(1.0, in: marks) == "1:1")
        #expect(SettingsRow.nearestMark(1.4, in: marks) == "4:3")
        #expect(SettingsRow.nearestMark(1.45, in: marks) == "3:2")
        // the value is written as the shortest number
        #expect(SettingsRow.sliderText(1.5) == "1.5")
        #expect(SettingsRow.sliderText(0.5625) == "0.5625")
        #expect(SettingsRow.sliderText(1) == "1")
        #expect(SettingsRow.sliderText(1.33333333) == "1.3333")
    }
}
