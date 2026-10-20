import Testing
import Foundation
import SwiftUI
@testable import SettingsKit

/// The folder note (a row's «This folder: …» and «Use Default»), toggles that keep their nested rows active, and
/// colour rows over named values.
@MainActor
struct FolderNoteTests {
    @Test func folderOverrideFollowsTheStore() {
        let store = MemoryStore(values: ["upscale": "lanczos3"], defaults: ["upscale": "lanczos3"])
        store.folder = ["upscale": "bilinear"]
        let model = SettingsModel(store: store)
        model.register([page([.text("upscale", "Upscale"), .text("toast", "Toast")])])
        #expect(model.folderOverride("upscale") == "bilinear")
        #expect(model.folderOverride("toast") == nil)
        // The folder changed (another window, `S`): seen after the app's refresh.
        store.folder = ["upscale": "mitchell", "toast": "1"]
        #expect(model.folderOverride("upscale") == "bilinear")
        model.refreshFolderOverrides()
        #expect(model.folderOverride("upscale") == "mitchell")
        #expect(model.folderOverride("toast") == "1")
        // …and after any announcement of the store.
        store.folder = [:]
        store.changeExternally(["upscale": "lanczos2"])
        #expect(model.folderOverride("upscale") == nil)
        #expect(model.folderOverride("toast") == nil)
    }

    @Test func useDefaultAsksTheStore() {
        let store = MemoryStore(values: [:], defaults: ["upscale": "lanczos3"])
        store.folder = ["upscale": "bilinear"]
        let model = SettingsModel(store: store)
        model.register([page([.text("upscale", "Upscale")])])
        model.clearFolderOverride("upscale")
        #expect(store.clearedFolderKeys == ["upscale"])
        #expect(model.folderOverride("upscale") == nil)
        // loupe.conf is not written
        #expect(store.values.isEmpty)
    }

    @Test func folderNoteNamesTheChoice() {
        let choice = SettingsRow.choice("upscale", "Upscale", [("bilinear", "Bilinear"), ("lanczos3", "Lanczos-3")])
        #expect(FolderNote.text("bilinear", row: choice) == "Bilinear")
        #expect(FolderNote.text("ewa", row: choice) == "ewa")
        let toggle = SettingsRow.toggle("vibrance", "Vibrance")
        #expect(FolderNote.text("yes", row: toggle) == "On")
        #expect(FolderNote.text("no", row: toggle) == "Off")
        #expect(FolderNote.text("0.7", row: .number("amount", "Amount")) == "0.7")
    }

    @Test func toggleWithoutOffKeepsNestedActive() {
        #expect(SettingsRow.toggle("a", "A").turnsNestedOff(value: "no"))
        let folderSwitch = SettingsRow.toggle("vibrance", "Vibrance", nested: [.number("vibrance-amount", "Amount")],
                                              off: [])
        #expect(!folderSwitch.turnsNestedOff(value: "no"))
        #expect(!folderSwitch.turnsNestedOff(value: "yes"))
        // a raw row of kind toggle dims as before
        #expect(SettingsRow(key: "t", kind: .toggle, title: "T").turnsNestedOff(value: "no"))
    }

    @Test func colourNamesResolve() {
        let names = ["light": "#ffffff,#cccccc", "black": "#000000"]
        #expect(ColorText.resolved("light", names: names) == "#ffffff,#cccccc")
        #expect(ColorText.resolved(" Black ", names: names) == "#000000")
        #expect(ColorText.resolved("#123456", names: names) == "#123456")
        let row = SettingsRow.color("checker-colors", "Checker", count: 2, names: names)
        #expect(row.colorNames == names)
        #expect(SettingsRow.color("background", "Background").colorNames.isEmpty)
    }

    @Test func wellOverANameKeepsTheOtherColour() {
        let names = ["light": "#ffffff,#cccccc"]
        let store = MemoryStore(values: ["checker-colors": "light"], defaults: ["checker-colors": "light"])
        let model = SettingsModel(store: store)
        ColorWell.commit(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1), model: model, key: "checker-colors",
                         index: 0, count: 2, names: names)
        #expect(store.values["checker-colors"] == "#000000,#cccccc")
        // the colour the name already has: nothing to write
        store.changeExternally(["checker-colors": "light"])
        ColorWell.commit(Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1), model: model, key: "checker-colors",
                         index: 0, count: 2, names: names)
        #expect(store.values["checker-colors"] == "light")
    }
}
