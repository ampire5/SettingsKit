# SettingsKit architecture

Current implementation map. Update when state ownership or settings/page lifetime changes. This package owns
settings presentation; the application owns the meaning, validation and persistence of its settings.

## Components and ownership

- `Sources/SettingsKit/SettingsStore.swift`: main-actor application adapter protocol. Values are strings; the store
  supplies defaults, validation, writes, resets and override/machine notes. The kit does not parse an app config file.
- `Sources/SettingsKit/SettingsDescription.swift`: declarative page/section/row descriptions.
- `Sources/SettingsKit/SettingsModel.swift`: model registration, per-key observable state and store coordination.
- `Sources/SettingsKit/SettingsWindow.swift`: `SettingsWindowController`, application-retained reusable window,
  page selection, placement, editing completion and keyboard-loop behavior.
- `Sources/SettingsKit/PageView.swift`, `RowViews.swift`, `SidebarView.swift`, `CardView.swift`: SwiftUI presentation.
- `Sources/SettingsKit/KeyBindingTable.swift` / `KeyBindingSheet.swift`: binding editing and capture.
- `Sources/SettingsKit/IconPickerWindow.swift` / `IconChoices.swift`: icon selection UI.

`SettingsKit` is the single library target; `settings-demo` is a standalone integration example. There are no
external package dependencies. Application-specific pages and config stores live in LoupeSettings/FrameScrubSettings.

## Data flow and responsiveness

Application creates store/model/pages → controller registers pages → a row reads its key's state → edit is validated
and written through the store → that key's state updates. Navigation belongs to separate UI state, not every row.
Pages already built are retained when hidden. Avoid rebuilding pages on navigation or propagating changing
modifiers through all inactive controls. Store callbacks are on the main actor: slow persistence must be handled by
the application adapter without blocking input. `Debouncer.swift` coalesces delayed edits; complete editing when
switching pages or closing the window. Pop-up choices should remain lazy until first opening.

## Where to change and verify

| Work | Start | Verification |
|---|---|---|
| Validation/override semantics | `SettingsStore.swift`, `SettingsModel.swift` in `Sources/SettingsKit` | `Tests/SettingsKitTests` |
| Page lifecycle/navigation | `Sources/SettingsKit/SettingsWindow.swift`, `Sources/SettingsKit/PageView.swift` | retained page and real-window navigation tests/bench |
| Controls | `Sources/SettingsKit/RowViews.swift` | control tests and first-open/return CPU measurements |
| Application setting | App's settings target and store | app settings tests and real settings window bench |

Run `swift test --jobs 4`. Use `settings-demo` for manual integration; application `LoupeBench settings` and
`FrameScrubBench settings` cover their real pages. Measure main-thread CPU over repeated first/return navigation;
model-only tests do not establish UI responsiveness. See [usage](../README.md) for the public API.
