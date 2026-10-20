import Testing
import Foundation
import Observation
@testable import SettingsKit

private final class Flag: @unchecked Sendable { var isSet = false }

@MainActor
struct ModelTests {
    @Test func modelReadsStoreThenDefault() {
        let store = MemoryStore(values: ["a": "yes"], defaults: ["a": "no", "b": "250"])
        let model = SettingsModel(store: store)
        #expect(model.value("a") == "yes")
        #expect(model.value("b") == "250")
    }

    @Test func setWritesThroughValidate() {
        let store = MemoryStore(values: ["n": "1"],
                                validate: { v, k in k == "n" && Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.set("n", "x")
        #expect(store.values["n"] == "1")
        #expect(model.errors["n"] == "Not a valid value")
        #expect(model.value("n") == "1")
        model.set("n", "3")
        #expect(store.values["n"] == "3")
        #expect(model.errors["n"] == nil)
        #expect(model.value("n") == "3")
    }

    @Test func throwingStoreKeepsValue() {
        let store = MemoryStore(values: ["a": "no"])
        store.writeError = DiskFull()
        let model = SettingsModel(store: store)
        model.set("a", "yes")
        #expect(model.writeFailure?.message == DiskFull().localizedDescription)
        #expect(model.value("a") == "no")
        #expect(store.values["a"] == "no")
    }

    @Test func storeChangeRefreshesModel() {
        let store = MemoryStore(values: ["a": "1", "b": "1"])
        let model = SettingsModel(store: store)
        #expect(model.value("a") == "1")
        let fired = Flag()
        withObservationTracking { _ = model.value("a") } onChange: { fired.isSet = true }
        store.changeExternally(["a": "2"])
        #expect(fired.isSet)
        #expect(model.value("a") == "2")
    }

    @Test func otherStoresAreIgnored() {
        let store = MemoryStore(values: ["a": "1"])
        let model = SettingsModel(store: store)
        model.register([page([.number("a", "A")])])
        MemoryStore(values: ["a": "9"]).changeExternally(["a": "9"])
        #expect(model.value("a") == "1")
    }

    @Test func draftSurvivesExternalChange() {
        let store = MemoryStore(values: ["a": "5"])
        let model = SettingsModel(store: store)
        model.beginEditing("a")
        #expect(model.draft("a") == "5")
        model.updateDraft("a", "12")
        store.changeExternally(["a": "99"])
        #expect(model.draft("a") == "12")
        #expect(model.value("a") == "99")
        model.commit("a")
        #expect(store.values["a"] == "12")
        #expect(model.draft("a") == nil)
    }

    @Test func rejectedCommitKeepsDraftUntilCancel() {
        let store = MemoryStore(values: ["a": "5"], validate: { v, _ in v == "bad" ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.beginEditing("a")
        model.updateDraft("a", "bad")
        model.commit("a")
        #expect(store.values["a"] == "5")
        #expect(model.draft("a") == "bad")
        #expect(model.errors["a"] == "Not a valid value")
        model.cancelEditing("a")
        #expect(model.draft("a") == nil)
        #expect(model.errors["a"] == nil)
        #expect(model.value("a") == "5")
    }

    @Test func unchangedCommitDoesNotWrite() {
        let store = MemoryStore(defaults: ["a": "5"])
        let model = SettingsModel(store: store)
        model.beginEditing("a")
        model.commit("a")
        #expect(store.values["a"] == nil)
        #expect(model.draft("a") == nil)
    }

    @Test func numberAcceptsCommaDecimal() {
        #expect(SettingsModel.normalizedNumber("1,5") == "1.5")
        #expect(SettingsModel.normalizedNumber("  250 ") == "250")
        let store = MemoryStore(values: ["n": "2"], validate: { v, _ in Double(v) == nil ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N", unit: "×", step: 0.1)])])
        model.beginEditing("n")
        model.updateDraft("n", "1,5")
        model.commit("n")
        #expect(store.values["n"] == "1.5")
        #expect(model.errors["n"] == nil)
        #expect(model.draft("n") == nil)
    }

    @Test func emptyNumberIsNotWritten() {
        let store = MemoryStore(values: ["n": "2"])
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N")])])
        model.beginEditing("n")
        model.updateDraft("n", " ")
        model.commit("n")
        #expect(store.values["n"] == "2")
        #expect(model.draft("n") == nil)
    }

    @Test func numberStepsThroughSet() {
        let store = MemoryStore(values: ["n": "2000", "f": "1.5"],
                                validate: { v, _ in (Double(v) ?? -1) < 0 ? "Not a valid value" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.number("n", "N", unit: "ms", step: 50), .number("f", "F", step: 0.1)])])
        model.step("n", by: 50)
        #expect(store.values["n"] == "2050")
        model.step("n", by: -500)
        #expect(store.values["n"] == "1550")
        model.step("f", by: 0.1)
        #expect(store.values["f"] == "1.6")
        model.beginEditing("n")
        model.step("n", by: 50)
        #expect(store.values["n"] == "1600")
        #expect(model.draft("n") == "1600")
        model.step("n", by: -5000)
        #expect(store.values["n"] == "1600")
        #expect(model.errors["n"] == "Not a valid value")
    }

    @Test func stepIgnoresNonFiniteAndHugeNumbers() {
        let bad = ["nan", "inf", "-inf", "1e20"]
        for text in bad {
            // a value written by hand in the file
            let store = MemoryStore(values: ["n": text])
            let model = SettingsModel(store: store)
            model.register([page([.number("n", "N", unit: "ms", step: 50)])])
            model.step("n", by: 50)
            model.step("n", by: -500)
            #expect(store.values["n"] == text)
            #expect(model.errors["n"] == nil)
            // a typed draft
            store.values["n"] = "100"
            model.beginEditing("n")
            model.updateDraft("n", text)
            model.step("n", by: 50)
            #expect(store.values["n"] == "100")
            #expect(model.draft("n") == text)
            #expect(model.errors["n"] == nil)
        }
    }

    @Test func formatIsSafeForAnyDouble() {
        for number in [Double.nan, .infinity, -.infinity, 1e20, -1e20, Double.greatestFiniteMagnitude] {
            #expect(!SettingsModel.format(number, places: 0).isEmpty)
            #expect(!SettingsModel.format(number, places: 2).isEmpty)
        }
        #expect(SettingsModel.format(2050, places: 0) == "2050")
        #expect(SettingsModel.format(1.6, places: 1) == "1.6")
    }

    @Test func folderOverrideDefaultsAreInert() {
        let store = MemoryStore()
        #expect(store.folderOverride(forKey: "a") == nil)
        store.clearFolderOverride(forKey: "a")
    }
}
