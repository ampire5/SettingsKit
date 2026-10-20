# SettingsKit

A SwiftUI settings window for macOS apps (Loupe now, FrameScrub next), laid out after IINA 1.5's settings: a sidebar with a search field, pages with SF Symbols and the sub-sections of the open page, and on the right cards of rows — switches, pop-ups, number and text fields, chevron rows that open in place, nested rows. Changes apply at once, with no Apply button. Own code; IINA served only as the visual reference.

An app describes its pages as data (`SettingsPage` → `SettingsSection` → `SettingsCard` → `SettingsRow`, built with `.toggle(…)`, `.choice(…)`, `.number(…)`, `.text(…)`, `.flags(…)`, `.button(…)`, `.group(…)`), supplies a `SettingsStore` — the key/value source of truth, for example a config file: `value(forKey:)`, `defaultValue(forKey:)`, `validate(_:forKey:)`, `setValue(_:forKey:)`, posting `.settingsStoreDidChange` for every change, its own writes included — and opens a `SettingsWindowController(pages:model:autosaveName:lastPageDefaultsKey:style:)` over a `SettingsModel(store:)`. `style` is `.glass` by default (a floating Liquid Glass sidebar panel and glass cards over a softly tinted window) or `.plain` (the stock sidebar, opaque cards).

`swift run settings-demo` shows a sample (`--page <id>`, `--search <text>`, `--light`, `--style plain|glass`). macOS 26+, Swift 5 language mode.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ampire5/SettingsKit.git", from: "0.1.0"),
],
// in your target:
dependencies: [.product(name: "SettingsKit", package: "SettingsKit")]
```

Used by [Loupe](https://github.com/ampire5/Loupe).

## License

MIT — see [LICENSE](LICENSE).
