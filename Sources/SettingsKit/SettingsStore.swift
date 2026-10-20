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
    /// The value set for the current folder only, if any.
    func folderOverride(forKey key: String) -> String?
    func clearFolderOverride(forKey key: String)
}

public extension SettingsStore {
    func folderOverride(forKey key: String) -> String? { nil }
    func clearFolderOverride(forKey key: String) {}
}

public extension Notification.Name {
    /// Posted by a store when values changed. `object` is the store, `userInfo["keys"]` the `[String]` of changed keys.
    static let settingsStoreDidChange = Notification.Name("SettingsKit.settingsStoreDidChange")
}
