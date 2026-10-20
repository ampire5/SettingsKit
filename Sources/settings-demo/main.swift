// settings-demo: IINA 1.5's General page (texts as the visual reference) and a page with every row kind,
// over an in-memory store.
//
//   --page <id>        open a page (general, kinds, ui, …)
//   --search <text>    preset the search field
//   --expand <row id>  open a chevron row (repeatable)
//   --set <key=value>  write a value (repeatable), to show the modified dot
//   --write-fail <key> after --set, make the store refuse writes and try <key> once (the alert sheet)
//   --error            write an invalid value once, to show a row's error text
//   --light            light appearance (default dark)
//   --size <W>x<H>     content size in points (default 782x637)
//   --no-activate      do not bring the app to the front
//   --style <s>        plain | glass (default glass)
//   --bind <in=action> bind an input on the Key Bindings page first (repeatable; `ignore` unbinds)

import AppKit
import SettingsKit

// MARK: - Store

@MainActor
final class DemoStore: SettingsStore {
    private var values: [String: String] = [:]
    var refusesWrites = false
    private let defaults: [String: String]
    private let ranges: [String: ClosedRange<Double>]

    init(defaults: [String: String], ranges: [String: ClosedRange<Double>]) {
        self.defaults = defaults
        self.ranges = ranges
    }

    func value(forKey key: String) -> String? { values[key] }
    func defaultValue(forKey key: String) -> String { defaults[key] ?? "no" }

    func validate(_ value: String, forKey key: String) -> String? {
        if let range = ranges[key] {
            guard let number = Double(value), range.contains(number) else { return "Not a valid value" }
        }
        if key == "background" || key == "unreadable-color",
           ColorText.colors(value)?.count != 1 { return "Not a valid colour: #rrggbb" }
        if key == "checker-colors", ColorText.colors(value)?.count != 2 {
            return "Not a valid value: two colours, such as #333333,#666666"
        }
        if key == "zoom-stops" {
            let ok = value.split(separator: ",").allSatisfy { part in
                part.hasSuffix("%") && Double(part.dropLast()) != nil
            }
            if !ok { return "Not a valid value: a comma list of percentages, such as 50%,100%" }
        }
        return nil
    }

    struct Refused: LocalizedError {
        var errorDescription: String? { "The file \u{201C}loupe.conf\u{201D} is read-only." }
    }

    func setValue(_ value: String, forKey key: String) throws {
        if refusesWrites { throw Refused() }
        values[key] = value
        print("set \(key)=\(value)")
        NotificationCenter.default.post(name: .settingsStoreDidChange, object: self, userInfo: ["keys": [key]])
    }
}

// MARK: - Pages

/// Defaults of the IINA texts' switches (keys are made from the titles).
nonisolated(unsafe) var iinaDefaults: [String: String] = [:]

func slug(_ title: String) -> String {
    title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        .split(separator: "-").joined(separator: "-")
}

/// A switch with IINA's text, on or off by default.
func sw(_ title: String, _ symbol: String? = nil, _ on: Bool = false, description: String? = nil,
        nested: [SettingsRow] = []) -> SettingsRow {
    let key = slug(title)
    iinaDefaults[key] = on ? "yes" : "no"
    return .toggle(key, title, symbol: symbol, description: description, nested: nested)
}

func menu(_ title: String, _ symbol: String?, _ options: [String]) -> SettingsRow {
    let key = slug(title)
    iinaDefaults[key] = slug(options[0])
    return .choice(key, title, options.map { (word: slug($0), title: $0) }, symbol: symbol)
}

let generalPage = SettingsPage("general", "General", symbol: "gear", sections: [
    SettingsSection("Behavior", [
        SettingsCard([
            menu("At launch", "rectangle.badge.sparkles", ["Show welcome window", "Show open panel", "Do nothing"]),
            .group("When media is opened", symbol: "doc.badge.clock", expands: [
                sw("Pause"), sw("Enter full screen"),
            ]),
            .group("Pause/resume when", symbol: "arrow.trianglehead.2.clockwise.rotate.90.circle", expands: [
                sw("Window is minimized", nil, true), sw("Application is inactive"),
                sw("Entering full screen: play"), sw("Leaving full screen: pause"),
                sw("System goes to sleep", nil, true),
            ]),
        ]),
        SettingsCard([
            sw("Allow multiple player windows", "macwindow.on.rectangle", false, nested: [
                sw("Group media in playlist when opening multiple files at once"),
                sw("Allow opening the same file in multiple windows"),
            ]),
            sw("Quit after all windows are closed", "rectangle.badge.xmark"),
            sw("Keep window open after playback finishes", "pause.rectangle", true),
        ]),
        SettingsCard([
            sw("Use legacy full screen", "arrow.up.left.and.arrow.down.right.rectangle"),
            sw("Black out other monitors while in full screen", "lock.display", true),
            sw("Prevent screen saver from starting while playing", "tv.slash", true, nested: [
                sw("Not while in \"music mode\" or only playing audio", nil, false,
                   description: "Still prevents system from sleeping."),
            ]),
        ]),
        SettingsCard([
            sw("Switch to \"music mode\" automatically when playing an audio file", "music.note.list", true),
        ]),
        SettingsCard([
            sw("Check for updates automatically", "arrowshape.up.circle", true, nested: [sw("Receive beta updates")]),
        ]),
    ]),
    SettingsSection("History", rows: [
        sw("Resume last playback position", "clock.arrow.trianglehead.counterclockwise.rotate.90", true),
        sw("Record playback history", "play.rectangle", true),
        sw("Record recent files", "doc.on.doc", true, nested: [
            sw("Track all files in \"Open Recent\" menu", nil, false,
               description: "Includes files opened from Finder and the command line."),
        ]),
    ]),
    SettingsSection("Playlist", rows: [
        sw("Add files in the same folder to the playlist", "text.badge.plus", true),
        sw("Play next item automatically", "play.square.stack", true),
        sw("Show artist and track name for audio files", "music.mic", true, nested: [sw("Only in \"music mode\"")]),
        sw("Repeat by default", "repeat"),
    ]),
    SettingsSection("Screenshots", rows: [
        sw("Save screenshots to folder", "camera.on.rectangle", true),
        menu("Format", nil, ["PNG", "JPEG", "HEIC", "TIFF", "WebP"]),
        sw("Copy to clipboard", "list.clipboard"),
        sw("Include subtitles", "captions.bubble", true),
        sw("Show preview after taking a screenshot", "eye", true),
    ]),
])

/// The other IINA sidebar pages, with a few placeholder rows each.
func simplePage(_ id: String, _ title: String, _ symbol: String, _ sections: [(String, [SettingsRow])]) -> SettingsPage {
    SettingsPage(id, title, symbol: symbol, sections: sections.map { SettingsSection($0.0, rows: $0.1) })
}

let iinaPages: [SettingsPage] = [
    generalPage,
    simplePage("ui", "Interface", "macwindow", [
        ("Window", [sw("Resize window to fit video size", "arrow.up.left.and.arrow.down.right", true),
                    sw("Remember window position", "macwindow", true),
                    menu("Initial window size", "rectangle.dashed", ["Video size", "Fixed", "Fit screen"])]),
        ("On Screen Controller", [menu("Layout", "rectangle.bottomthird.inset.filled", ["Floating", "Top", "Bottom"]),
                                  sw("Show chapter positions", "list.number", true)]),
    ]),
    simplePage("video", "Video", "photo.tv", [
        ("Video", [sw("Enable hardware decoder", "cpu", true), sw("Use EDR when available", "sun.max", true)]),
    ]),
    simplePage("audio", "Audio", "waveform", [
        ("Audio", [menu("Audio device", "hifispeaker", ["Auto"]), sw("Enable spatial audio", "airpods")]),
    ]),
    simplePage("subtitles", "Subtitles", "captions.bubble", [
        ("Auto load", [sw("Load subtitles in the same folder", "folder", true),
                       menu("Default encoding", "textformat", ["Auto detect", "UTF-8"])]),
    ]),
    simplePage("network", "Network", "globe", [
        ("Cache", [sw("Enable cache", "internaldrive", true), sw("Use system proxy", "network", true)]),
    ]),
    simplePage("control", "Control", "computermouse", [
        ("Trackpad", [sw("Scroll to seek", "hand.draw", true), sw("Pinch to resize window", "hand.pinch", true)]),
    ]),
    simplePage("keybindings", "Key Bindings", "keyboard", [
        ("Configuration", [menu("Key binding set", "keyboard", ["IINA Default", "mpv Default"]),
                           sw("Use media keys", "playpause", true)]),
    ]),
    simplePage("advanced", "Advanced", "flask", [
        ("Advanced", [sw("Enable advanced settings", "flask"), sw("Use mpv's OSD", "text.bubble"),
                      sw("Write log to file", "doc.text")]),
    ]),
    simplePage("plugins", "Plugins", "puzzlepiece.extension", [
        ("Plugins", [sw("Allow plugins to open new windows", "macwindow.badge.plus", true)]),
    ]),
    simplePage("utilities", "Utilities", "wrench.and.screwdriver", [
        ("Default application", [sw("Set IINA as the default application", "app.badge.checkmark")]),
        ("Clear cache", [sw("Clear playback history", "trash")]),
    ]),
]

/// Every row kind, with Loupe-like keys.
let kindsPage = SettingsPage("kinds", "All Kinds", symbol: "square.grid.2x2", sections: [
    SettingsSection("Switches", rows: [
        .toggle("vibrance", "Vibrance", symbol: "camera.filters",
                description: "Boosts muted colours and leaves saturated ones alone.", nested: [
                    .number("vibrance-amount", "Amount", unit: "%", step: 5, description: "0–100 %, default 30."),
                ]),
        .toggle("auto-color", "Auto colour", symbol: "wand.and.stars",
                description: "Off, so its nested rows are disabled.", nested: [
                    .choice("auto-color-method", "Method", [("levels", "Levels"), ("gray-world", "Grey world")]),
                    .number("auto-color-strength", "Strength", unit: "%", step: 5),
                ]),
    ]),
    SettingsSection("Choices and Numbers", rows: [
        .choice("default-zoom-mode", "Default zoom", [("fit", "Fit to window"), ("fit-width", "Fit width"),
                                                      ("100%", "Actual size")],
                symbol: "plus.magnifyingglass", description: "Zoom of a newly opened image."),
        .number("toast-duration", "Notification duration", unit: "ms", step: 50, symbol: "clock",
                description: "250–5000 ms, default 2000. ↑/↓ step 50, ⇧↑/⇧↓ 500."),
        .number("rmb-zoom-speed", "Right-button zoom speed", unit: "×", step: 0.1, symbol: "computermouse",
                description: "0.1–10, default 1. A comma decimal (1,5) is written as 1.5."),
        .number("cache-memory", "Memory cache", unit: "GB", step: 0.5, symbol: "memorychip",
                description: "0.5–64 GB."),
    ]),
    SettingsSection("Text", rows: [
        .text("zoom-stops", "Zoom stops", placeholder: "25%,50%,100%", symbol: "list.number",
              description: "A comma list of percentages, e.g. 25%,50%,100%,200%,400%."),
    ]),
    SettingsSection("Expanding", rows: [
        .flags("auto-color-filters", "Auto colour filters",
               [("levels", "Levels"), ("curves", "Curves"), ("white-balance", "White balance")],
               symbol: "slider.horizontal.3", description: "Each filter is a word of a comma list."),
        .group("Pan indicators", symbol: "arrow.up.and.down.and.arrow.left.and.right", expands: [
            .toggle("pan-indicators-on-switch", "Show on image switch"),
            .number("pan-indicators-fade", "Fade", unit: "ms", step: 50),
        ]),
    ]),
    SettingsSection("Actions", rows: [
        .button("Configuration file", "Open loupe.conf", symbol: "doc.text") { print("open loupe.conf") },
        .button("Configuration folder", "Reveal in Finder", symbol: "folder") { print("reveal") },
    ]),
])

/// Round-icon pictures drawn for the icon row (stand-ins for an app's icon alternates).
@MainActor func demoIcon(_ color: NSColor, _ symbol: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
        color.setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 28, yRadius: 28).fill()
        if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 64, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: (128 - size.width) / 2, y: (128 - size.height) / 2, width: size.width, height: size.height))
        }
        return true
    }
    return image
}

/// Colour and icon rows with Loupe-like keys.
let colorsPage = SettingsPage("colors", "Colour and Icon", symbol: "paintpalette", sections: [
    SettingsSection("Colours", rows: [
        .color("background", "Background", symbol: "square.fill",
               description: "One colour, #rrggbb (#rgb is read too)."),
        .color("checker-colors", "Transparency checkerboard", count: 2, symbol: "checkerboard.rectangle",
               description: "Two colours, comma-separated: #333333,#666666."),
        .color("unreadable-color", "Unreadable value", symbol: "questionmark.square.dashed",
               description: "The text is kept as it is and the well is grey until you change it."),
    ]),
    SettingsSection("Icon", rows: [
        .icon("app-icon", "App icon", choices: {
            [("owl", demoIcon(.systemPurple, "bird.fill")), ("horse", demoIcon(.systemOrange, "hare.fill")),
             ("glass", demoIcon(.systemTeal, "magnifyingglass")), ("plain", nil)]
        }, symbol: "app.badge", description: "Pictures are 32 pt in the menu."),
    ]),
])

let kindsDefaults: [String: String] = [
    "vibrance": "yes", "vibrance-amount": "30", "auto-color": "no", "auto-color-method": "levels",
    "auto-color-strength": "50", "default-zoom-mode": "fit", "toast-duration": "2000", "rmb-zoom-speed": "1",
    "cache-memory": "4", "zoom-stops": "25%,50%,100%,200%,400%", "auto-color-filters": "levels,curves",
    "pan-indicators-on-switch": "yes", "pan-indicators-fade": "300",
    "background": "#333333", "checker-colors": "#333333,#666666", "unreadable-color": "dark gray", "app-icon": "owl",
]

let kindsRanges: [String: ClosedRange<Double>] = [
    "vibrance-amount": 0...100, "auto-color-strength": 0...100, "toast-duration": 250...5000,
    "rmb-zoom-speed": 0.1...10, "cache-memory": 0.5...64, "pan-indicators-fade": 0...2000,
]

// MARK: - Key bindings

/// An in-memory binding table: a few keys and buttons, `ignore` for «−» on a built-in row.
@MainActor
final class DemoBindingSource: KeyBindingSource {
    private struct Binding { var action: String; var step: Double?; var source: String }
    private let titles: [String: String] = [
        "next": "Next photo", "previous": "Previous photo", "fit": "Fit to window", "fill": "Fill the window",
        "toggle-vibrance": "Vibrance on/off (this folder)", "add vibrance-amount": "Vibrance amount",
        "toggle-info-panel": "Show or hide the info panel", "next-folder": "Next folder", "zoom-step": "Zoom step",
    ]
    private let builtIn: [(id: String, input: String, action: String, step: Double?, mouse: Bool)] = [
        ("RIGHT", "→", "next", nil, false), ("LEFT", "←", "previous", nil, false), ("f", "F", "fit", nil, false),
        ("v", "V", "toggle-vibrance", nil, false), ("i", "I", "toggle-info-panel", nil, false),
        ("MBTN_MID", "Middle", "fill", nil, true), ("MX_GESTURE+WHEEL", "Gesture button + wheel", "add vibrance-amount", 0.05, true),
        ("MBTN_BACK+WHEEL", "Back + wheel", "next-folder", nil, true), ("MBTN_FORWARD+WHEEL", "Forward + wheel", "zoom-step", nil, true),
    ]
    private var file: [String: Binding] = [:]

    nonisolated init() {}

    func rows() -> [KeyBindingRowModel] {
        var ids = builtIn.map(\.id)
        ids += file.keys.filter { !ids.contains($0) }.sorted()
        return ids.map { id in
            let base = builtIn.first { $0.id == id }
            let mouse = base?.mouse ?? id.contains("_")
            if let b = file[id] {
                let off = b.action == "ignore"
                return KeyBindingRowModel(id: id, input: base?.input ?? id, action: off ? "Unbound" : title(b.action, b.step),
                                          source: off ? "off" : "input.conf", isMouse: mouse,
                                          actionID: off ? nil : b.action, step: b.step, canRestore: true, canRemove: !off)
            }
            return KeyBindingRowModel(id: id, input: base!.input, action: title(base!.action, base!.step), source: "built-in",
                                      isMouse: mouse, actionID: base!.action, step: base!.step)
        }
    }

    private func title(_ action: String, _ step: Double?) -> String {
        (titles[action] ?? action) + (step.map { " ±\($0)" } ?? "")
    }

    func actionGroups() -> [(group: String, actions: [(id: String, title: String, takesStep: Bool)])] {
        [("Navigation", [("next", "Next photo", false), ("previous", "Previous photo", false)]),
         ("Zoom", [("fit", "Fit to window", false), ("fill", "Fill the window", false), ("zoom-step", "Zoom step", false)]),
         ("Colour", [("toggle-vibrance", "Vibrance on/off (this folder)", false), ("add vibrance-amount", "Vibrance amount", true)]),
         ("View", [("toggle-info-panel", "Show or hide the info panel", false)]),
         ("Folder", [("next-folder", "Next folder", false)])]
    }

    func mouseButtons() -> [(id: String, title: String)] {
        [("MBTN_MID", "Middle"), ("MBTN_BACK", "Back"), ("MBTN_FORWARD", "Forward"), ("MX_PANEL", "Panel")]
    }

    func pressKinds(for button: String) -> [(id: String, title: String, enabled: Bool)] {
        [(button, "Tap", true), (button + "-long", "Long press", true), (button + "+WHEEL", "+ wheel", true),
         ("MBTN_RIGHT+" + button, "With right button", button == "MBTN_MID")]
    }

    func keyToken(for event: NSEvent) -> Result<String, KeyBindingRefusal> {
        if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            return .failure(KeyBindingRefusal("⌘ and ⌃ shortcuts belong to the menus"))
        }
        guard let c = event.charactersIgnoringModifiers, c.count == 1 else { return .failure(KeyBindingRefusal("This key cannot be bound")) }
        return .success(event.modifierFlags.contains(.shift) ? c.uppercased() : c.lowercased())
    }

    func conflict(input: String) -> String? {
        rows().first { $0.id == input && $0.actionID != nil }?.action
    }

    func bind(input: String, action: String, step: Double?) throws {
        file[input] = Binding(action: action, step: step, source: "input.conf")
        changed()
    }

    func remove(rowID: String) throws {
        if file[rowID] != nil { file[rowID] = nil } else { file[rowID] = Binding(action: "ignore", step: nil, source: "off") }
        changed()
    }

    func restoreBuiltIn(rowID: String) throws {
        file[rowID] = nil
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .settingsStoreDidChange, object: self, userInfo: ["keys": ["bindings"]])
    }
}

@MainActor let demoBindings = DemoBindingSource()

@MainActor let bindingsPage = SettingsPage("bindings", "Key Bindings", symbol: "keyboard", sections: [
    SettingsSection("Keyboard", rows: [
        .custom("Keyboard bindings", searchTexts: {
            demoBindings.rows().filter { !$0.isMouse }.flatMap { [$0.input, $0.id, $0.action] }
        }) { KeyBindingTable(source: demoBindings, mouse: false) },
    ]),
    SettingsSection("Mouse", rows: [
        .custom("Mouse bindings", searchTexts: {
            demoBindings.rows().filter(\.isMouse).flatMap { [$0.input, $0.id, $0.action] }
        }) { KeyBindingTable(source: demoBindings, mouse: true) },
    ]),
])

// MARK: - App

enum Args {
    static let all = CommandLine.arguments
    static func value(_ name: String) -> String? {
        guard let i = all.firstIndex(of: name), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
    static func values(_ name: String) -> [String] {
        all.indices.filter { all[$0] == name && $0 + 1 < all.count }.map { all[$0 + 1] }
    }
    static var size: NSSize {
        let parts = (value("--size") ?? "").split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : NSSize(width: 782, height: 637)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: SettingsWindowController?

    func applicationWillFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: Args.all.contains("--light") ? .aqua : .darkAqua)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let pages = [iinaPages[0], kindsPage, colorsPage, bindingsPage] + iinaPages.dropFirst()
        let store = DemoStore(defaults: iinaDefaults.merging(kindsDefaults) { $1 }, ranges: kindsRanges)
        let model = SettingsModel(store: store)
        let controller = SettingsWindowController(pages: pages, model: model, autosaveName: "SettingsKitDemo",
                                                  lastPageDefaultsKey: "settingsDemoLastPage",
                                                  style: SettingsStyle(rawValue: Args.value("--style") ?? "") ?? .glass)
        self.controller = controller
        if let query = Args.value("--search") { controller.search(query) }
        for row in Args.values("--expand") { controller.expand(row) }
        for pair in Args.values("--set") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { model.set(parts[0], parts[1]) }
        }
        if let key = Args.value("--write-fail") {
            store.refusesWrites = true
            model.set(key, "yes")
        }
        if Args.all.contains("--error") { model.set("cache-memory", "100") }
        for pair in Args.values("--bind") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[1] == "ignore" { try? demoBindings.remove(rowID: parts[0]) } else { try? demoBindings.bind(input: parts[0], action: parts[1], step: nil) }
        }
        controller.show(page: Args.value("--page") ?? "general")
        controller.window?.setContentSize(Args.size)
        if !Args.all.contains("--no-activate") { NSApp.activate() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
