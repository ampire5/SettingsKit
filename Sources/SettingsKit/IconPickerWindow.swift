import AppKit
import SwiftUI

/// A window to pick the app's Dock icon from: the picture grid (`IconGridView`) — search, sections, packs, the current
/// one ringed, arrow keys and Return, and with a `folder` its Show in Finder, Add… and drop. A picture click applies it
/// at once (the Dock shows it, so there is nothing to confirm); a pack opens its pictures. Esc or the close button
/// closes the window. The app keeps one and calls `show()` from a menu item.
///
///     let picker = IconPickerWindowController(title: "App Icon",
///                                             choices: { Settings.appIconChoices() },     // [IconChoice]
///                                             folder: Settings.userIcons,
///                                             current: { config.appIcon },
///                                             onPick: { config.set("app-icon", $0) })
@MainActor
public final class IconPickerWindowController: NSWindowController {
    private let model: IconGridModel

    /// - Parameters:
    ///   - title: the window's title.
    ///   - choices: the pictures, by the value the app stores, read each time the window is shown and when `folder`
    ///     changes.
    ///   - folder: where the user's own pictures go, or nil (no folder buttons, no drop).
    ///   - current: the value now in effect.
    ///   - onPick: called with the value the user picked.
    public init(title: String = "App Icon",
                choices: @escaping @MainActor () -> [IconChoice],
                folder: URL? = nil,
                current: @escaping @MainActor () -> String,
                onPick: @escaping @MainActor (String) -> Void) {
        model = IconGridModel(choices: choices, folder: folder, current: current, onPick: onPick)
        let host = NSHostingController(rootView: IconPickerView(model: model))
        host.view.frame = NSRect(x: 0, y: 0, width: 560, height: 440)
        let window = NSWindow(contentRect: host.view.frame,
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.contentViewController = host
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 260)
        window.setFrameAutosaveName("IconPicker")
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// Reads the choices again and brings the window to the front.
    public func show() {
        model.resetNavigation()
        model.reload()
        model.scrollTarget = model.highlighted
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct IconPickerView: View {
    let model: IconGridModel

    var body: some View {
        IconGridView(model: model, side: 84)
            .padding(.top, 24)          // under the transparent title bar
            .frame(minWidth: 320, minHeight: 240)
            .onExitCommand { NSApp.keyWindow?.close() }
    }
}
