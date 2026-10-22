import Foundation
import Observation

/// The views' side of a `SettingsStore`: current values, per-key error texts and the drafts of fields being
/// edited. Writes go through `validate`, then `setValue`; the store announces every change (its own writes
/// included) with `.settingsStoreDidChange`, and the model refreshes only the listed keys.
@MainActor @Observable
public final class SettingsModel {
    @ObservationIgnored public let store: SettingsStore

    /// key → value as last read from the store (registered and announced keys).
    private var values: [String: String] = [:]
    /// key → error text of the last rejected or failed write; cleared by the next good write or `cancelEditing`.
    public private(set) var errors: [String: String] = [:]
    /// The last write the store could not perform (no permission, full disk): the key and the error text. The
    /// window shows it as an alert and clears it; the row keeps the store's value.
    public private(set) var writeFailure: (key: String, message: String)?
    /// key → text typed into a field that has not been committed yet.
    private var drafts: [String: String] = [:]
    /// key → the value the current folder sets for itself (`SettingsStore.folderOverride`), for the registered keys
    /// that have one: the rows' folder note.
    private var folderOverrides: [String: String] = [:]
    /// key → the store's note about the key's value on this machine (`SettingsStore.machineNote`), for the registered
    /// keys that have one: the rows' machine note.
    private var machineNotes: [String: SettingsNote] = [:]

    @ObservationIgnored private var numberKeys: Set<String> = []
    /// The keys of the registered pages, in order (the folder overrides and machine notes are asked for them).
    @ObservationIgnored private var registeredKeys: [String] = []
    @ObservationIgnored private nonisolated(unsafe) var observer: NSObjectProtocol?

    public init(store: SettingsStore) {
        self.store = store
        observer = NotificationCenter.default.addObserver(
            forName: .settingsStoreDidChange, object: store, queue: nil
        ) { [weak self] note in
            let keys = note.userInfo?["keys"] as? [String] ?? []
            MainActor.assumeIsolated {
                self?.refresh(keys)
                self?.refreshFolderOverrides()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Reads the keys of `pages` and learns which keys are numbers (their text is normalized on write).
    public func register(_ pages: [SettingsPage]) {
        for row in pages.flatMap(\.rows) {
            guard let key = row.key else { continue }
            switch row.kind {
            case .number, .slider: numberKeys.insert(key)
            default: break
            }
        }
        let keys = pages.flatMap(\.keys)
        registeredKeys += keys.filter { !registeredKeys.contains($0) }
        refresh(keys)
        refreshFolderOverrides()
    }

    // MARK: Folder

    /// The value the current folder sets for `key` itself, or nil (the row then shows no folder note). Asked of the
    /// store on `register`, on every announcement of the store and on `refreshFolderOverrides()`.
    public func folderOverride(_ key: String) -> String? { folderOverrides[key] }

    /// «Use Default»: the folder drops its own value of `key` (the store's `clearFolderOverride`); the file is not
    /// written.
    public func clearFolderOverride(_ key: String) {
        store.clearFolderOverride(forKey: key)
        refreshFolderOverrides()
    }

    /// Asks the store again for every registered key's folder value: for the app to call when the current folder or
    /// its values changed (another window became main, a key in the viewer set a folder value).
    public func refreshFolderOverrides() {
        var found: [String: String] = [:]
        var notes: [String: SettingsNote] = [:]
        for key in registeredKeys {
            if let value = store.folderOverride(forKey: key) { found[key] = value }
            if let note = store.machineNote(forKey: key) { notes[key] = note }
        }
        if found != folderOverrides { folderOverrides = found }
        if notes != machineNotes { machineNotes = notes }
    }

    // MARK: Machine

    /// The store's note about `key`'s value on this machine, or nil (the row then shows none). Refreshed together
    /// with the folder overrides: on `register`, on every announcement of the store and on `refreshFolderOverrides()`.
    public func machineNote(_ key: String) -> SettingsNote? { machineNotes[key] }

    /// «Use recommended»: writes the note's recommended value for `key` (as `set` does); nothing when the note has
    /// none.
    public func useRecommended(_ key: String) {
        guard let recommended = machineNotes[key]?.recommended else { return }
        set(key, recommended)
    }

    // MARK: Values

    /// The store's value, or its default when the key is not set.
    public func value(_ key: String) -> String {
        values[key] ?? storeValue(key)
    }

    /// Validates and writes `value`. A rejected write keeps the old value and sets `errors[key]`; one the store
    /// fails (`setValue` throws) keeps it too and sets `writeFailure`; a good one clears `errors[key]`. Number keys are normalized first (`1,5` → `1.5`); an empty number is not written.
    public func set(_ key: String, _ value: String) {
        var text = value
        if numberKeys.contains(key) {
            text = Self.normalizedNumber(text)
            if text.isEmpty { refresh([key]); return }
        }
        if let message = store.validate(text, forKey: key) {
            fail(key, message)
            return
        }
        do {
            try store.setValue(text, forKey: key)
        } catch {
            // The row returns to the file's value: no stale error, no draft; the alert carries the message.
            drafts[key] = nil
            if errors[key] != nil { errors[key] = nil }
            writeFailure = (key, error.localizedDescription)
            reannounce(key)
            return
        }
        if errors[key] != nil { errors[key] = nil }
        refresh([key])
    }

    /// Reset to Default: the store forgets the key (`removeValues`) and its default applies again, after dropping the
    /// key's draft and error. A store that fails keeps the value and sets `writeFailure`.
    public func reset(_ key: String) {
        reset([key])
    }

    /// Reset Page to Defaults: `reset` for every key of `page` that differs from its default, in one store call.
    public func resetPage(_ page: SettingsPage) {
        reset(modifiedKeys(in: page))
    }

    /// The keys of `page` whose value differs from the default, in order (the page's reset button is off without them).
    public func modifiedKeys(in page: SettingsPage) -> [String] {
        var seen: Set<String> = []
        return page.keys.filter { seen.insert($0).inserted && isModified($0) }
    }

    /// Whether the key's value differs from the store's default (the dot beside a row's title).
    public func isModified(_ key: String) -> Bool {
        value(key) != store.defaultValue(forKey: key)
    }

    /// The alert has been dismissed.
    public func clearWriteFailure() { writeFailure = nil }

    /// `1,5` → `1.5`; surrounding spaces removed.
    public static func normalizedNumber(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    }

    // MARK: Editing

    /// A field took focus: its draft starts from the current value.
    public func beginEditing(_ key: String) {
        if drafts[key] == nil { drafts[key] = value(key) }
    }

    /// The uncommitted text of the field for `key`, if it is being edited. Store changes do not touch it.
    public func draft(_ key: String) -> String? { drafts[key] }

    public func updateDraft(_ key: String, _ text: String) {
        if drafts[key] != text { drafts[key] = text }
    }

    /// Enter or focus loss: writes the draft. An unchanged draft is dropped without a write; a rejected one
    /// stays (with `errors[key]`) until it is fixed or cancelled.
    public func commit(_ key: String) {
        guard let draft = drafts[key] else { return }
        let text = numberKeys.contains(key) ? Self.normalizedNumber(draft) : draft
        if text == value(key) {
            drafts[key] = nil
            if errors[key] != nil { errors[key] = nil }
            return
        }
        set(key, draft)
        if errors[key] == nil { drafts[key] = nil }
    }

    /// Esc: drops the draft and the error; the field shows the store's value again.
    public func cancelEditing(_ key: String) {
        drafts[key] = nil
        if errors[key] != nil { errors[key] = nil }
    }

    /// ↑/↓ in a number field: writes the current number (draft or value) plus `delta` through `set`.
    /// While editing, the draft follows a good write. Text that is not an ordinary number (`nan`, `inf`,
    /// `1e20`, words) is left alone: no step, no write, no error — `validate` judges it on commit.
    func step(_ key: String, by delta: Double) {
        let current = Self.normalizedNumber(drafts[key] ?? value(key))
        guard let number = Double(current), Self.isSteppable(number), Self.isSteppable(number + delta) else { return }
        let text = Self.format(number + delta, places: max(Self.decimalPlaces(current), Self.decimalPlaces(delta)))
        set(key, text)
        if errors[key] == nil, drafts[key] != nil { drafts[key] = text }
    }

    // MARK: Private

    private func reset(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        for key in keys {
            drafts[key] = nil
            if errors[key] != nil { errors[key] = nil }
        }
        do {
            try store.removeValues(forKeys: keys)
        } catch {
            writeFailure = (keys[0], error.localizedDescription)
            keys.forEach(reannounce)
            return
        }
        refresh(keys)
    }

    private func storeValue(_ key: String) -> String {
        store.value(forKey: key) ?? store.defaultValue(forKey: key)
    }

    private func refresh(_ keys: [String]) {
        for key in keys {
            let new = storeValue(key)
            if values[key] != new { values[key] = new }
        }
    }

    /// Records the error and re-announces the key, so a control that already moved (a switch, a menu)
    /// returns to the store's value.
    private func fail(_ key: String, _ message: String) {
        errors[key] = message
        reannounce(key)
    }

    private func reannounce(_ key: String) {
        values[key] = storeValue(key)
    }

    private static func decimalPlaces(_ text: String) -> Int {
        guard let dot = text.firstIndex(of: ".") else { return 0 }
        return text.distance(from: dot, to: text.endIndex) - 1
    }

    private static func decimalPlaces(_ number: Double) -> Int {
        var places = 0
        var x = abs(number)
        while places < 6, abs(x - x.rounded()) > 1e-9 { x *= 10; places += 1 }
        return places
    }

    /// Finite and well inside `Int` (and exact `Double` integers): the range ↑/↓ steps in.
    private static func isSteppable(_ number: Double) -> Bool {
        number.isFinite && abs(number) < 1e15
    }

    /// `number` with `places` decimals; never traps (non-finite or huge numbers print as `Double` does).
    static func format(_ number: Double, places: Int) -> String {
        guard isSteppable(number) else { return String(number) }
        if places == 0 { return String(Int(number.rounded())) }
        return String(format: "%.\(min(places, 6))f", number)
    }
}
