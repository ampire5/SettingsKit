import Testing
@testable import SettingsKit

@MainActor
struct DescriptionTests {
    private let zoomPage = SettingsPage("zoom", "Zoom & Pan", symbol: "plus.magnifyingglass", sections: [
        SettingsSection("Zoom", rows: [
            .toggle("zoom-animation", "Animate zoom", description: "Eases the zoom between stops.", nested: [
                .number("zoom-animation-ms", "Duration", unit: "ms", step: 10),
            ]),
            .group("Rubber band", expands: [
                .toggle("zoom-rubber-band", "Rubber band at the limits"),
                .choice("rubber-band", "Style", [("soft", "Soft"), ("hard", "Hard")]),
            ]),
            .flags("auto-color-filters", "Filters", [("levels", "Levels"), ("curves", "Curves")]),
        ]),
        SettingsSection("Pan & Inertia", rows: [
            .text("zoom-stops", "Zoom stops", placeholder: "25%,50%,100%"),
            .button("Open loupe.conf", "Open") {},
        ]),
    ])

    @Test func pageKeysFlattenNestedAndExpanding() {
        #expect(zoomPage.keys == ["zoom-animation", "zoom-animation-ms", "zoom-rubber-band", "rubber-band",
                                  "auto-color-filters", "zoom-stops"])
        #expect(zoomPage.rows.map(\.title) == ["Animate zoom", "Duration", "Rubber band", "Rubber band at the limits",
                                               "Style", "Filters", "Zoom stops", "Open loupe.conf"])
        if case .flags(let key, let items) = zoomPage.rows[5].kind {
            #expect(key == "auto-color-filters")
            #expect(items.map(\.word) == ["levels", "curves"])
        } else {
            Issue.record("flags row has kind \(zoomPage.rows[5].kind)")
        }
        #expect(Set(zoomPage.rows.map(\.id)).count == zoomPage.rows.count)
    }

    @Test func searchFindsTitleDescriptionAndSection() {
        let other = page([.toggle("x", "Something else")], id: "other", section: "Other")
        let search = SettingsSearch(pages: [zoomPage, other])
        // description
        #expect(search.matches("ease").map(\.rowID) == ["zoom-animation"])
        #expect(search.matches("ease").map(\.page) == ["zoom"])
        // title, case-insensitive, nested and expanding rows included
        #expect(search.matches("DURATION").map(\.rowID) == ["zoom-animation-ms"])
        #expect(search.matches("limits").map(\.rowID) == ["zoom-rubber-band"])
        // a flags item title finds its row
        #expect(search.matches("curves").map(\.rowID) == ["auto-color-filters"])
        // section title: every row of the section
        #expect(search.matches("inertia").map(\.rowID) == ["zoom-stops", zoomPage.rows[7].id])
        #expect(search.matches("else").map(\.page) == ["other"])
        #expect(search.matches("  ").isEmpty)
        #expect(search.matches("nothing like this").isEmpty)
    }

    /// A page switch first lets the old page's field write its text (`willChangePage`), and only on a real switch.
    @Test func pageSwitchEndsEditingFirst() {
        let other = SettingsPage("other", "Other", symbol: "gear", sections: [])
        let ui = SettingsUIState(pages: [zoomPage, other], page: nil)
        var calls: [String] = []
        ui.willChangePage = { calls.append("will:" + ui.page) }
        ui.onPageChange = { calls.append("did:" + $0) }
        ui.select("zoom")
        ui.select("other")
        #expect(calls == ["will:zoom", "did:other"])
    }

    /// Nested rows go inactive while their parent is off: a switch that is not `yes`, a pop-up or a
    /// number on one of its `off` values; other parents never turn them off.
    @Test func parentIsOffDecidesNestedRows() {
        let toggle = SettingsRow.toggle("vibrance", "Vibrance")
        #expect(toggle.turnsNestedOff(value: "no"))
        #expect(!toggle.turnsNestedOff(value: "yes"))
        let choice = SettingsRow.choice("pan-indicators", "Pan indicators", [("auto", "Auto"), ("no", "Off")])
        #expect(choice.turnsNestedOff(value: "no"))
        #expect(!choice.turnsNestedOff(value: "auto"))
        let custom = SettingsRow.choice("strip-window", "Strip", [("overlay", "Overlay"), ("off", "Off")], off: ["off"])
        #expect(custom.turnsNestedOff(value: "off"))
        #expect(!custom.turnsNestedOff(value: "no"))
        let number = SettingsRow.number("strip-magnify", "Magnify", off: ["1"])
        #expect(number.turnsNestedOff(value: "1"))
        #expect(!number.turnsNestedOff(value: "2"))
        #expect(!SettingsRow.number("toast-duration", "Duration").turnsNestedOff(value: "0"))
        #expect(!SettingsRow.text("zoom-stops", "Stops").turnsNestedOff(value: "no"))
    }
}
