import AppKit
import SwiftUI

/// A window to pick the app's Dock icon from: a grid of the available pictures with their names, the current one
/// ringed. A click applies it at once (the Dock shows it, so there is nothing to confirm); Esc or the close button
/// closes the window. The app keeps one and calls `show()` from a menu item.
///
///     let picker = IconPickerWindowController(title: "App Icon",
///                                             choices: { Settings.appIconChoices() },
///                                             current: { config.appIcon },
///                                             onPick: { config.set("app-icon", $0) })
@MainActor
public final class IconPickerWindowController: NSWindowController {
    private let state: IconPickerState
    private let choices: @MainActor () -> [(word: String, image: NSImage?)]
    private let current: @MainActor () -> String

    /// - Parameters:
    ///   - title: the window's title.
    ///   - choices: the pictures, by the value the app stores, read each time the window is shown.
    ///   - current: the value now in effect.
    ///   - onPick: called with the value the user clicked.
    public init(title: String = "App Icon",
                choices: @escaping @MainActor () -> [(word: String, image: NSImage?)],
                current: @escaping @MainActor () -> String,
                onPick: @escaping @MainActor (String) -> Void) {
        self.choices = choices
        self.current = current
        state = IconPickerState(onPick: onPick)
        let host = NSHostingController(rootView: IconPickerView(state: state))
        host.view.frame = NSRect(x: 0, y: 0, width: 560, height: 420)
        let window = NSWindow(contentRect: host.view.frame,
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.contentViewController = host
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 240)
        window.setFrameAutosaveName("IconPicker")
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// Reads the choices again and brings the window to the front.
    public func show() {
        state.items = choices().map { IconPickerState.Item(word: $0.word, image: $0.image) }
        state.current = current()
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor @Observable
final class IconPickerState {
    struct Item: Identifiable {
        let word: String
        let image: NSImage?
        var id: String { word }
    }

    var items: [Item] = []
    var current = ""
    let onPick: @MainActor (String) -> Void

    init(onPick: @escaping @MainActor (String) -> Void) { self.onPick = onPick }

    func pick(_ word: String) {
        guard word != current else { return }
        current = word
        onPick(word)
    }
}

struct IconPickerView: View {
    let state: IconPickerState
    private static let side: CGFloat = 84

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.side + 24), spacing: 8)], spacing: 12) {
                ForEach(state.items) { item in
                    IconCell(item: item, selected: item.word == state.current, side: Self.side)
                        .onTapGesture { state.pick(item.word) }
                }
            }
            .padding(20)
            .padding(.top, 8)
        }
        .frame(minWidth: 320, minHeight: 240)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}

private struct IconCell: View {
    let item: IconPickerState.Item
    let selected: Bool
    let side: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = item.image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "questionmark.app.dashed").resizable().scaledToFit()
                        .foregroundStyle(.tertiary).padding(side / 5)
                }
            }
            .frame(width: side, height: side)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
            )
            Text(item.word)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .frame(width: side + 24)
        .contentShape(Rectangle())
        .help(item.word)
    }
}
