import Foundation

/// The key/value source of truth behind a settings window (for example a config file).
/// Values are strings as they appear in the file (`yes`, `250`, `fit-width,100%`); the rows convert them.
@MainActor
public protocol SettingsStore: AnyObject {
    /// The stored value, or nil when the key is not set.
    func value(forKey key: String) -> String?
    /// The value the app uses when the key is not set.
    func defaultValue(forKey key: String) -> String
    /// nil when `value` is acceptable for `key`, otherwise the error text to show.
    func validate(_ value: String, forKey key: String) -> String?
    func setValue(_ value: String, forKey key: String) throws
    /// Reset to Default: the keys are no longer set, so their defaults apply again. One call for a whole page.
    func removeValues(forKeys keys: [String]) throws
    /// The value set for the current folder only, if any.
    func folderOverride(forKey key: String) -> String?
    func clearFolderOverride(forKey key: String)
}

public extension SettingsStore {
    /// Writes each key's default value. A store that can drop a key should, so a default that depends on the machine
    /// (memory, cores) keeps following it rather than staying at the number written today.
    func removeValues(forKeys keys: [String]) throws {
        for key in keys { try setValue(defaultValue(forKey: key), forKey: key) }
    }

    func folderOverride(forKey key: String) -> String? { nil }
    func clearFolderOverride(forKey key: String) {}
}

public extension Notification.Name {
    /// Posted by a store when values changed. `object` is the store, `userInfo["keys"]` the `[String]` of changed keys.
    static let settingsStoreDidChange = Notification.Name("SettingsKit.settingsStoreDidChange")
}
