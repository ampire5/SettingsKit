import Testing
import Foundation
@testable import SettingsKit

/// The machine note (a row's «this value is not ideal for this Mac» and «Use recommended»).
@MainActor
struct MachineNoteTests {
    @Test func machineNoteFollowsTheStore() {
        let store = MemoryStore(values: ["a": "9"], defaults: ["a": "2"])
        store.notes = ["a": SettingsNote(severity: .suboptimal, text: "Above the cores", recommended: "2")]
        let model = SettingsModel(store: store)
        model.register([page([.text("a", "A"), .text("b", "B")])])
        #expect(model.machineNote("a") == SettingsNote(severity: .suboptimal, text: "Above the cores", recommended: "2"))
        #expect(model.machineNote("b") == nil)
        // The value changed and the store no longer has a note: gone after the announcement.
        store.notes = [:]
        store.changeExternally(["a": "2"])
        #expect(model.machineNote("a") == nil)
        // …and the app can ask again.
        store.notes = ["b": SettingsNote(severity: .harmful, text: "Too many", recommended: nil)]
        model.refreshFolderOverrides()
        #expect(model.machineNote("b")?.severity == .harmful)
        #expect(model.machineNote("b")?.recommended == nil)
    }

    @Test func useRecommendedWritesTheValue() {
        let store = MemoryStore(values: ["a": "9"], defaults: ["a": "2"])
        store.notes = ["a": SettingsNote(severity: .suboptimal, text: "Above the cores", recommended: "2")]
        let model = SettingsModel(store: store)
        model.register([page([.text("a", "A")])])
        model.useRecommended("a")
        #expect(store.value(forKey: "a") == "2")
    }

    @Test func useRecommendedWithoutOneWritesNothing() {
        let store = MemoryStore(values: ["a": "9"], defaults: ["a": "2"])
        store.notes = ["a": SettingsNote(severity: .harmful, text: "Too many", recommended: nil)]
        let model = SettingsModel(store: store)
        model.register([page([.text("a", "A")])])
        model.useRecommended("a")
        #expect(store.value(forKey: "a") == "9")
    }

    @Test func machineNoteDefaultsAreInert() {
        let store = BareStore()
        #expect(store.machineNote(forKey: "a") == nil)
        let model = SettingsModel(store: store)
        model.register([page([.text("a", "A")])])
        #expect(model.machineNote("a") == nil)
    }
}

/// A store that implements only the required methods.
@MainActor
private final class BareStore: SettingsStore {
    func value(forKey key: String) -> String? { nil }
    func defaultValue(forKey key: String) -> String { "" }
    func validate(_ value: String, forKey key: String) -> String? { nil }
    func setValue(_ value: String, forKey key: String) throws {}
}
