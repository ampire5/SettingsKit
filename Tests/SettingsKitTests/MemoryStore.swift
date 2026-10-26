import Foundation
@testable import SettingsKit

/// Test double: a dictionary with defaults and a validate closure; posts `.settingsStoreDidChange` on write,
/// as a real store does for its own writes.
@MainActor
final class MemoryStore: SettingsStore {
    var values: [String: String]
    var defaults: [String: String]
    var validator: (String, String) -> String?
    /// When set, `setValue` throws it and writes nothing.
    var writeError: Error?
    /// The current folder's own values (`folderOverride`).
    var folder: [String: String] = [:]
    /// Each `removeValues` call's keys, in order.
    var removedBatches: [[String]] = []
    /// The keys `clearFolderOverride` was called with, in order.
    var clearedFolderKeys: [String] = []
    /// Levels with a label of their own (`override`); a key not here falls back to `folder`.
    var overrides: [String: SettingsOverride] = [:]
    /// The store's machine notes by key (`machineNote`).
    var notes: [String: SettingsNote] = [:]

    init(values: [String: String] = [:], defaults: [String: String] = [:],
         validate: @escaping (String, String) -> String? = { _, _ in nil }) {
        self.values = values
        self.defaults = defaults
        self.validator = validate
    }

    func value(forKey key: String) -> String? { values[key] }
    func defaultValue(forKey key: String) -> String { defaults[key] ?? "" }
    func validate(_ value: String, forKey key: String) -> String? { validator(value, key) }
    func setValue(_ value: String, forKey key: String) throws {
        if let writeError { throw writeError }
        values[key] = value
        announce([key])
    }

    func removeValues(forKeys keys: [String]) throws {
        if let writeError { throw writeError }
        removedBatches.append(keys)
        for key in keys { values[key] = nil }
        announce(keys)
    }

    func folderOverride(forKey key: String) -> String? { folder[key] }
    func override(forKey key: String) -> SettingsOverride? {
        overrides[key] ?? folder[key].map { SettingsOverride(value: $0) }
    }
    func machineNote(forKey key: String) -> SettingsNote? { notes[key] }
    func clearFolderOverride(forKey key: String) {
        clearedFolderKeys.append(key)
        folder[key] = nil
    }

    /// An outside change (another app, a menu item): set the values, then post.
    func changeExternally(_ changes: [String: String]) {
        for (key, value) in changes { values[key] = value }
        announce(Array(changes.keys))
    }

    private func announce(_ keys: [String]) {
        NotificationCenter.default.post(name: .settingsStoreDidChange, object: self, userInfo: ["keys": keys])
    }
}

struct DiskFull: LocalizedError {
    var errorDescription: String? { "The disk is full." }
}

/// A one-page description around `rows`, for model and description tests.
func page(_ rows: [SettingsRow], id: String = "p", section: String = "Section") -> SettingsPage {
    SettingsPage(id, "Page", symbol: "gearshape", sections: [SettingsSection(section, rows: rows)])
}
