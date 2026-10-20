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

    @Test func resetWritesDefault() {
        let store = MemoryStore(values: ["n": "300"], defaults: ["n": "250"],
                                validate: { v, _ in Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N")])])
        model.beginEditing("n")
        model.updateDraft("n", "x")
        model.commit("n")
        #expect(model.errors["n"] != nil)
        model.reset("n")
        #expect(store.values["n"] == "250")
        #expect(model.value("n") == "250")
        #expect(model.errors["n"] == nil)
        #expect(model.draft("n") == nil)
    }

    @Test func resetAtDefaultStillWritesTheLine() {
        let store = MemoryStore(values: [:], defaults: ["a": "no"])
        let model = SettingsModel(store: store)
        model.reset("a")
        #expect(store.values["a"] == "no")
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
}
