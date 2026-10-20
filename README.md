# SettingsKit

A SwiftUI settings window for macOS apps (Loupe now, FrameScrub next), laid out after IINA 1.5's settings: a sidebar with a search field, pages with SF Symbols and the sub-sections of the open page, and on the right cards of rows — switches, pop-ups, number and text fields, chevron rows that open in place, nested rows. Changes apply at once, with no Apply button. Own code; IINA served only as the visual reference.

An app describes its pages as data (`SettingsPage` → `SettingsSection` → `SettingsCard` → `SettingsRow`, built with `.toggle(…)`, `.choice(…)`, `.number(…)`, `.text(…)`, `.flags(…)`, `.button(…)`, `.group(…)`), supplies a `SettingsStore` — the key/value source of truth, for example a config file: `value(forKey:)`, `defaultValue(forKey:)`, `validate(_:forKey:)`, `setValue(_:forKey:)`, posting `.settingsStoreDidChange` for every change, its own writes included — and opens a `SettingsWindowController(pages:model:autosaveName:lastPageDefaultsKey:style:)` over a `SettingsModel(store:)`. `style` is `.glass` by default (a floating Liquid Glass sidebar panel and glass cards over a softly tinted window) or `.plain` (the stock sidebar, opaque cards).

![Loupe's Mouse & Trackpad page in the glass style](https://raw.githubusercontent.com/ampire5/Loupe/main/docs/images/settings-mouse.webp)

What else is in the box:

- **Row types** beyond the basics: `.color(…)` (one or more colour wells over `#rrggbb[,#rrggbb]`, with named values
  such as `light` shown in the wells), `.icon(…)` (a pop-up of icon names with their images), and `.custom(…)` (a view
  of the app's own filling a card; the window's search asks its `searchTexts` on every query).
- **Key-binding editor**: `KeyBindingTable(source:mouse:note:)` is a SwiftUI table of keyboard or mouse bindings with a
  filter field, «+» / «−», an edit sheet with a key recorder, «Restore Built-in» and Delete. The app supplies a
  `KeyBindingSource` (rows, actions, mouse buttons and press kinds, `keyToken(for:)`, `bind`, `remove`,
  `restoreBuiltIn`); its `conflict(input:)` names the action an input does now, and the sheet shows «Replaces: …»
  before a binding takes it over. Put the table in a `.custom` row.
- **Per-folder overrides**: a store that knows folder values implements `folderOverride(forKey:)` and
  `clearFolderOverride(forKey:)` (both have empty defaults). A row whose key the current folder sets shows «This
  folder: <value>» with a «Use Default» button, which calls `SettingsModel.clearFolderOverride(_:)`; call
  `refreshFolderOverrides()` when the current folder changes.
- **Programmatic control** on `SettingsWindowController`: `show(page:)`, `search(_:)` (fills the search field),
  `expand(_:)` (opens a `.group` or `.flags` row by its id), `endEditing()` (commit a field before quitting).
- **Two styles**: `SettingsStyle.glass` (default) and `.plain`.

`swift run settings-demo` shows a sample (`--page <id>`, `--search <text>`, `--expand <row id>`, `--light`,
`--style plain|glass`).

Requirements: macOS 26+, swift-tools 6.2 (the target builds in the Swift 5 language mode).

## Usage

```swift
import AppKit
import SettingsKit

@MainActor final class DefaultsStore: SettingsStore {
    private let defaults = ["show-hidden": "no", "thumbnail-size": "160", "background": "#1e1e1e"]

    func value(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    func defaultValue(forKey key: String) -> String { defaults[key] ?? "" }
    func validate(_ value: String, forKey key: String) -> String? {
        if key == "thumbnail-size", !(Double(value).map { (40...480).contains($0) } ?? false) { return "40–480" }
        return nil
    }
    func setValue(_ value: String, forKey key: String) throws {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsStoreDidChange, object: self, userInfo: ["keys": [key]])
    }
}

let pages = [
    SettingsPage("general", "General", symbol: "gearshape", sections: [
        SettingsSection("Browser", rows: [
            .toggle("show-hidden", "Show hidden files", symbol: "eye"),
            .number("thumbnail-size", "Thumbnail size", unit: "pt", step: 20, symbol: "square.grid.2x2"),
            .color("background", "Background", symbol: "square.fill"),
        ]),
    ]),
]
let store = DefaultsStore()
let controller = SettingsWindowController(pages: pages, model: SettingsModel(store: store),
                                          autosaveName: "Settings", lastPageDefaultsKey: "SettingsLastPage")
controller.show(page: nil)
```

Keep `controller` alive. The model refreshes only the keys a store lists in `.settingsStoreDidChange`, posted with the
store as `object` for every change, the store's own writes included.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ampire5/SettingsKit.git", from: "0.1.0"),
],
// in your target:
dependencies: [.product(name: "SettingsKit", package: "SettingsKit")]
```

Used by [Loupe](https://github.com/ampire5/Loupe).

## Issues and contributions

Bug reports and pull requests are welcome at [github.com/ampire5/SettingsKit/issues](https://github.com/ampire5/SettingsKit/issues).
Please run `swift test` before sending a change.

## License

MIT — see [LICENSE](LICENSE).
