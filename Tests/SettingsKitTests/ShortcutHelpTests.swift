import AppKit
import Testing
@testable import SettingsKit

@MainActor
struct CheatSheetTests {
    @Test func searchesTheEffectiveBindingAndItsAction() {
        let fit = Self.sheet.filtered(by: "fit to window").flatMap { $0 }.flatMap(\.rows)
        #expect(fit.map(\.keys) == ["G"])
        #expect(Self.sheet.filtered(by: "g").flatMap { $0 }.flatMap(\.rows).contains { $0.title == "Fit to window" })
        #expect(Self.sheet.filtered(by: "  PINCH  ").flatMap { $0 }.flatMap(\.rows).contains { $0.keys == "Pinch" })
        #expect(Self.sheet.filtered(by: "no such binding").isEmpty)
    }

    private static let sheet = CheatSheetView.Sheet(columns: [
        [.init(title: "Navigation", rows: [("Left", "Previous photo"), ("Right", "Next photo")])],
        [.init(title: "View", rows: [("G", "Fit to window"), ("F", "Full screen")])],
        [.init(title: "Trackpad", rows: [("Pinch", "Zoom at the pointer"), ("Double tap", "Reset zoom")])],
    ])

    @Test func compactWindowKeepsEverySectionInReach() throws {
        _ = NSApplication.shared
        let help = CheatSheetView(frame: NSRect(x: 0, y: 0, width: 320, height: 210))
        help.show(Self.sheet)
        help.layoutSubtreeIfNeeded()
        let scroll = try #require(descendants(of: help).compactMap { $0 as? NSScrollView }.first)
        let document = try #require(scroll.documentView)
        #expect(help.bounds.contains(help.convert(scroll.bounds, from: scroll)))
        #expect(document.bounds.height > scroll.contentSize.height)
        #expect(document.bounds.width == scroll.contentSize.width)
        help.scrollPage(down: true)
        #expect(scroll.contentView.bounds.minY > 0)
        help.scrollPage(down: false)
        #expect(scroll.contentView.bounds.minY == 0)
        let narrowHeight = document.bounds.height
        help.frame.size = NSSize(width: 1400, height: 900)
        help.layoutSubtreeIfNeeded()
        #expect(document.bounds.height < narrowHeight)
    }

    @Test func usesDarkGlassThatBlursTheViewerBehindIt() throws {
        _ = NSApplication.shared
        let help = CheatSheetView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        help.show(Self.sheet)
        let glass = try #require(help.subviews.compactMap { $0 as? NSVisualEffectView }.first)
        #expect(glass.material == .hudWindow)
        #expect(glass.blendingMode == .withinWindow)
        #expect(glass.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        #expect(glass.layer?.masksToBounds == true)
    }

    @Test func searchUpdatesResultsAndDismissalRestoresFocus() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = try #require(window.contentView)
        let previous = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        container.addSubview(previous)
        #expect(window.makeFirstResponder(previous))
        let help = CheatSheetView(frame: container.bounds)
        container.addSubview(help)
        help.show(Self.sheet)
        help.layoutSubtreeIfNeeded()

        let search = try #require(descendants(of: help).compactMap { $0 as? NSSearchField }.first)
        #expect(search.currentEditor() != nil)
        #expect(window.firstResponder === search.currentEditor())
        let fields = { self.descendants(of: help).compactMap { $0 as? NSTextField } }
        search.stringValue = "pinch"
        help.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        help.layoutSubtreeIfNeeded()
        #expect(fields().contains { $0.stringValue.contains("Pinch   Zoom at the pointer") })
        #expect(!fields().contains { $0.stringValue.contains("Previous photo") })
        search.stringValue = "zzzzzzz"
        help.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        #expect(fields().contains { $0.stringValue == "No matching keys or gestures" && !$0.isHidden })
        help.hide()
        #expect(previous.currentEditor() != nil)
        #expect(window.firstResponder === previous.currentEditor())

        help.show(Self.sheet)
        #expect(search.stringValue.isEmpty)
        #expect(search.currentEditor() != nil)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
