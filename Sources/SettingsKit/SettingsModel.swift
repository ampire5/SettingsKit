import Foundation
import Observation

/// The views' side of a `SettingsStore`: current values, per-key error texts and the drafts of fields being
/// edited. Writes go through `validate`, then `setValue`; the store announces every change (its own writes
/// included) with `.settingsStoreDidChange`, and the model refreshes only the listed keys.
@MainActor @Observable
public final class SettingsModel {
    @ObservationIgnored public let store: SettingsStore

    /// key → the key's state (value, error, draft, folder value, machine note). Each key's state is observed on its
    /// own: a view that reads one key updates when that key changes, not when any key does. With one dictionary per
    /// kind of state, a change to any key updated every row of every page the window keeps (`keptPages`): 190 ms per
    /// changed setting with Loupe's 11 pages kept, against 80 ms with only the open page before (LoupeBench settings,
    /// Intel iMac).
    @ObservationIgnored private var slots: [String: KeySlot] = [:]
    /// key → error text of the last rejected or failed write; cleared by the next good write or `cancelEditing`.
    /// Reads every key; a view asks `error(_:)` for its own.
    public var errors: [String: String] { slots.compactMapValues(\.error) }
    /// The last write the store could not perform (no permission, full disk): the key and the error text. The
    /// window shows it as an alert and clears it; the row keeps the store's value.
    public private(set) var writeFailure: (key: String, message: String)?
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

    /// The value a level below the store (the current folder, a file) sets for `key`, with the level's name, or nil
    /// (the row then shows no note). Asked of the store on `register`, on every announcement of the store and on
    /// `refreshFolderOverrides()`.
    public func override(_ key: String) -> SettingsOverride? { slot(key).override }

    /// The value of `override(_:)`.
    public func folderOverride(_ key: String) -> String? { slot(key).override?.value }

    /// «Use Default»: the level shown drops its own value of `key` (the store's `clearFolderOverride`); the file is
    /// not written.
    public func clearFolderOverride(_ key: String) {
        store.clearFolderOverride(forKey: key)
        refreshFolderOverrides()
    }

    /// Asks the store again for every registered key's folder value and machine note (`machineNote`): for the app to
    /// call when the current folder or its values changed (another window became main, a key in the viewer set a
    /// folder value).
    public func refreshFolderOverrides() {
        for key in registeredKeys {
            let slot = slot(key)
            let value = store.override(forKey: key), note = store.machineNote(forKey: key)
            if slot.override != value { slot.override = value }
            if slot.machineNote != note { slot.machineNote = note }
        }
    }

    // MARK: Machine

    /// The store's note about `key`'s value on this machine, or nil (the row then shows none). Refreshed together
    /// with the folder overrides: on `register`, on every announcement of the store and on `refreshFolderOverrides()`.
    public func machineNote(_ key: String) -> SettingsNote? { slot(key).machineNote }

    /// «Use recommended»: writes the note's recommended value for `key` (as `set` does); nothing when the note has
    /// none.
    public func useRecommended(_ key: String) {
        guard let recommended = slots[key]?.machineNote?.recommended else { return }
        set(key, recommended)
    }

    // MARK: Values

    /// The store's value, or its default when the key is not set.
    public func value(_ key: String) -> String {
        slot(key).value ?? storeValue(key)
    }

    /// The error text of the last rejected or failed write of `key`, or nil.
    public func error(_ key: String) -> String? { slot(key).error }

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
            slot(key).draft = nil
            clearError(key)
            writeFailure = (key, error.localizedDescription)
            reannounce(key)
            return
        }
        clearError(key)
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
        if slot(key).draft == nil { slot(key).draft = value(key) }
    }

    /// The uncommitted text of the field for `key`, if it is being edited. Store changes do not touch it.
    public func draft(_ key: String) -> String? { slot(key).draft }

    public func updateDraft(_ key: String, _ text: String) {
        if slot(key).draft != text { slot(key).draft = text }
    }

    /// Enter or focus loss: writes the draft. An unchanged draft is dropped without a write; a rejected one
    /// stays (with `errors[key]`) until it is fixed or cancelled.
    public func commit(_ key: String) {
        guard let draft = slot(key).draft else { return }
        let text = numberKeys.contains(key) ? Self.normalizedNumber(draft) : draft
        if text == value(key) {
            slot(key).draft = nil
            clearError(key)
            return
        }
        set(key, draft)
        if slot(key).error == nil { slot(key).draft = nil }
    }

    /// Esc: drops the draft and the error; the field shows the store's value again.
    public func cancelEditing(_ key: String) {
        if slot(key).draft != nil { slot(key).draft = nil }
        clearError(key)
    }

    /// ↑/↓ in a number field: writes the current number (draft or value) plus `delta` through `set`.
    /// While editing, the draft follows a good write. Text that is not an ordinary number (`nan`, `inf`,
    /// `1e20`, words) is left alone: no step, no write, no error — `validate` judges it on commit.
    func step(_ key: String, by delta: Double) {
        let current = Self.normalizedNumber(slot(key).draft ?? value(key))
        guard let number = Double(current), Self.isSteppable(number), Self.isSteppable(number + delta) else { return }
        let text = Self.format(number + delta, places: max(Self.decimalPlaces(current), Self.decimalPlaces(delta)))
        set(key, text)
        if slot(key).error == nil, slot(key).draft != nil { slot(key).draft = text }
    }

    // MARK: Private

    private func reset(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        for key in keys {
            if slot(key).draft != nil { slot(key).draft = nil }
            clearError(key)
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

    /// The key's state, made on first use (a view that reads a key before the store announced it still observes it).
    private func slot(_ key: String) -> KeySlot {
        if let slot = slots[key] { return slot }
        let slot = KeySlot()
        slots[key] = slot
        return slot
    }

    private func clearError(_ key: String) {
        if slot(key).error != nil { slot(key).error = nil }
    }

    private func storeValue(_ key: String) -> String {
        store.value(forKey: key) ?? store.defaultValue(forKey: key)
    }

    private func refresh(_ keys: [String]) {
        for key in keys {
            let new = storeValue(key)
            if slot(key).value != new { slot(key).value = new }
        }
    }

    /// Records the error and re-announces the key, so a control that already moved (a switch, a menu)
    /// returns to the store's value.
    private func fail(_ key: String, _ message: String) {
        slot(key).error = message
        reannounce(key)
    }

    private func reannounce(_ key: String) {
        slot(key).value = storeValue(key)
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

/// One key's state in `SettingsModel`, observed apart from the other keys.
@MainActor @Observable
final class KeySlot {
    /// The value as last read from the store; nil until the key was registered or announced.
    var value: String?
    var error: String?
    /// Text typed into the key's field and not committed yet.
    var draft: String?
    /// The value a level below the store sets (the current folder, a file).
    var override: SettingsOverride?
    /// The store's note about the value on this machine.
    var machineNote: SettingsNote?
}
