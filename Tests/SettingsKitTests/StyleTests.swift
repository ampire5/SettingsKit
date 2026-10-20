import Testing
import Foundation
@testable import SettingsKit

@MainActor
struct StyleTests {
    private func controller(style: SettingsStyle? = nil) -> SettingsWindowController {
        let model = SettingsModel(store: MemoryStore())
        let pages = [page([.toggle("a", "A")])]
        // No frame autosave (an empty name); the window is never shown.
        let name = "", key = "settingsKitTestsStyleLastPage"
        if let style {
            return SettingsWindowController(pages: pages, model: model, autosaveName: name,
                                            lastPageDefaultsKey: key, style: style)
        }
        return SettingsWindowController(pages: pages, model: model, autosaveName: name, lastPageDefaultsKey: key)
    }

    @Test func styleDefaultsToGlass() {
        #expect(controller().style == .glass)
        #expect(controller(style: .plain).style == .plain)
    }

    @Test func styleRoundTripsRawValue() {
        for style in [SettingsStyle.plain, .glass] {
            #expect(SettingsStyle(rawValue: style.rawValue) == style)
        }
        #expect(SettingsStyle.plain.rawValue == "plain")
        #expect(SettingsStyle.glass.rawValue == "glass")
        #expect(SettingsStyle(rawValue: "glass-all") == nil)
    }

    @Test func glassSidebarKeepsA200PointPanel() {
        #expect(SettingsWindowController.sidebarWidth(.plain) == 200)
        #expect(SettingsWindowController.sidebarWidth(.glass) == 216)
        #expect(SettingsWindowController.sidebarWidth(.glass) - 2 * GlassMetrics.sidebarInset == 200)
    }
}
