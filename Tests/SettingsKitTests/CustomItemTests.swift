import Testing
import SwiftUI
import AppKit
@testable import SettingsKit

@MainActor
struct CustomItemTests {
    private func gray(_ white: Double) -> Color { Color(.sRGB, red: white, green: white, blue: white, opacity: 1) }

    @Test func colorHexRoundTrips() {
        #expect(ColorText.hex(gray(0.2)) == "#333333")
        #expect(ColorText.hex(Color(.sRGB, red: 1, green: 0, blue: 0.5, opacity: 1)) == "#ff0080")
        let short = ColorText.colors("#333")
        #expect(short?.count == 1)
        #expect(short.map { ColorText.hex($0[0]) } == "#333333")
        let long = ColorText.colors(" #AbCdEf ")
        #expect(long.map { ColorText.hex($0[0]) } == "#abcdef")
        let two = ColorText.colors("#333333, #666")
        #expect(two?.map(ColorText.hex) == ["#333333", "#666666"])
    }

    @Test func unreadableColourTextIsNil() {
        for text in ["", "red", "#12", "#12345", "#1234567", "#gggggg", "333333", "#333333,", "#333333,blue"] {
            #expect(ColorText.colors(text) == nil, "\(text)")
        }
    }

    @Test func twoColoursWriteList() {
        #expect(ColorText.text([gray(0.2), gray(0.4)]) == "#333333,#666666")
        // One picker changed: the other part is kept as it stands.
        #expect(ColorText.updating("#333333,#666666", index: 1, to: gray(0.6), count: 2) == "#333333,#999999")
        #expect(ColorText.updating("#333333,#666666", index: 0, to: gray(0.6), count: 2) == "#999999,#666666")
        // Unreadable or missing parts stay as typed / become neutral grey.
        #expect(ColorText.updating("#333333,oops", index: 0, to: gray(0.6), count: 2) == "#999999,oops")
        #expect(ColorText.updating("", index: 1, to: gray(0.2), count: 2) == "#808080,#333333")
        #expect(ColorText.updating("#111", index: 0, to: gray(0.2), count: 1) == "#333333")

        let store = MemoryStore(values: ["checker-colors": "#333333,#666666"])
        let model = SettingsModel(store: store)
        let row = SettingsRow.color("checker-colors", "Checker colours", count: 2)
        model.register([page([row])])
        guard case .color(let count) = row.kind else { Issue.record("not a colour row"); return }
        #expect(count == 2)
        model.set("checker-colors", ColorText.updating(model.value("checker-colors"), index: 1, to: gray(0.6), count: count))
        #expect(store.values["checker-colors"] == "#333333,#999999")
    }

    @Test func iconChoiceWritesWord() {
        let store = MemoryStore(values: ["app-icon": "owl"])
        let model = SettingsModel(store: store)
        let row = SettingsRow.icon("app-icon", "App icon", choices: { [IconChoice(word: "owl"), IconChoice(word: "horse")] })
        model.register([page([row])])
        guard case .icon(let choices, let folder) = row.kind else { Issue.record("not an icon row"); return }
        #expect(choices().map(\.word) == ["owl", "horse"])
        #expect(folder == nil)
        #expect(row.iconLookup == nil)
        let looked = SettingsRow.icon("app-icon", "App icon", choices: { [] }, current: { IconChoice(word: $0, section: "x") })
        #expect(looked.iconLookup?("hat")?.section == "x")
        model.set("app-icon", choices()[1].word)
        #expect(store.values["app-icon"] == "horse")
        #expect(model.value("app-icon") == "horse")
    }
}

/// A clock the test advances by hand.
@MainActor
private final class FakeClock {
    private var timers: [(id: Int, due: TimeInterval, action: @MainActor () -> Void)] = []
    private var next = 0
    private(set) var now: TimeInterval = 0
    var scheduled = 0

    var schedule: Debouncer<String>.Schedule {
        { [self] delay, action in
            let id = next
            next += 1
            scheduled += 1
            timers.append((id, now + delay, action))
            return { [self] in timers.removeAll { $0.id == id } }
        }
    }

    func advance(_ seconds: TimeInterval) {
        now += seconds
        while let i = timers.firstIndex(where: { $0.due <= now }) {
            let timer = timers.remove(at: i)
            timer.action()
        }
    }
}

@MainActor
struct DebouncerTests {
    @Test func burstCommitsOnlyTheLastValueAfterThePause() {
        let clock = FakeClock()
        let debouncer = Debouncer<String>(delay: 0.25, schedule: clock.schedule)
        var committed: [String] = []
        for value in ["a", "b", "c"] {
            debouncer.submit(value) { committed.append($0) }
            clock.advance(0.1)
        }
        #expect(committed.isEmpty)
        #expect(debouncer.pending == "c")
        clock.advance(0.2)
        #expect(committed == ["c"])
        #expect(debouncer.pending == nil)
        clock.advance(1)
        #expect(committed == ["c"])
    }

    @Test func flushCommitsAtOnceAndOnlyOnce() {
        let clock = FakeClock()
        let debouncer = Debouncer<String>(delay: 0.25, schedule: clock.schedule)
        var committed: [String] = []
        debouncer.flush()
        #expect(committed.isEmpty)
        debouncer.submit("x") { committed.append($0) }
        debouncer.flush()
        #expect(committed == ["x"])
        clock.advance(1)
        #expect(committed == ["x"])
    }

    @Test func cancelDropsThePendingValue() {
        let clock = FakeClock()
        let debouncer = Debouncer<String>(delay: 0.25, schedule: clock.schedule)
        var committed: [String] = []
        debouncer.submit("x") { committed.append($0) }
        debouncer.cancel()
        debouncer.flush()
        clock.advance(1)
        #expect(committed.isEmpty)
        #expect(debouncer.pending == nil)
    }

    @Test func realClockCommitsAfterThePause() async throws {
        let debouncer = Debouncer<String>(delay: 0.05)
        var committed: [String] = []
        debouncer.submit("a") { committed.append($0) }
        debouncer.submit("b") { committed.append($0) }
        // Wait for the commit rather than a fixed time: a loaded CI machine can hold the main actor for a while.
        let deadline = ContinuousClock.now + .seconds(5)
        while committed.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(committed == ["b"])
    }
}

@MainActor
struct IconGridTests {
    /// A path is titled by its file name, so a long path stays readable.
    @Test func pathIsTitledByItsFileName() {
        #expect(IconChoice(word: "/Users/me/icons/gz1c.png").title == "gz1c.png")
        #expect(IconChoice(word: "~/x.png").title == "x.png")
        #expect(IconChoice(word: "owl").title == "owl")
    }

    @Test func searchFiltersByTitleAndKeepsSections() {
        let grid = IconGridModel(choices: {
            [IconChoice(word: "owl", section: "Built-in"), IconChoice(word: "horse", section: "Built-in"),
             IconChoice(word: "barn-owl", section: "Yours"), IconChoice(word: "/p/OWLET.png", section: "")]
        }, folder: nil, current: { "owl" }, onPick: { _ in })
        grid.reload()
        #expect(grid.sections.map(\.title) == ["Built-in", "Yours", ""])
        grid.query = " Owl "
        #expect(grid.sections.map { $0.items.map(\.word) } == [["owl"], ["barn-owl"], ["/p/OWLET.png"]])
        grid.query = "zebra"
        #expect(grid.sections.isEmpty)
    }

    @Test func pickWritesOnceAndHighlights() {
        var picked: [String] = []
        let grid = IconGridModel(choices: { [IconChoice(word: "owl"), IconChoice(word: "horse")] }, folder: nil,
                                 current: { "owl" }, onPick: { picked.append($0) })
        grid.reload()
        #expect(grid.highlighted == "owl")
        grid.pick("owl")
        grid.pick("horse")
        grid.pick("horse")
        #expect(picked == ["horse"])
        #expect(grid.current == "horse" && grid.highlighted == "horse")
    }

    @Test func packTileOpensPackBeforePickingAnIcon() throws {
        let pack = "/icons/flat"
        let first = "\(pack)/01.png", second = "\(pack)/02.png"
        var picked: [String] = []
        let grid = IconGridModel(choices: {
            [IconChoice(word: "owl", section: "Built-in"),
             IconChoice(word: first, section: "flat", pack: pack),
             IconChoice(word: second, section: "flat", pack: pack)]
        }, folder: nil, current: { second }, onPick: { picked.append($0) })
        grid.reload()

        let packTile = try #require(grid.sections.flatMap(\.items).first { $0.isPack })
        #expect(packTile.title == "flat")
        #expect(grid.highlighted == packTile.word)
        grid.activate(packTile.word)
        #expect(grid.openPack == pack)
        #expect(grid.sections.flatMap(\.items).map(\.word) == [first, second])
        #expect(picked.isEmpty)

        grid.activate(first)
        #expect(picked == [first])
        grid.closePack()
        #expect(grid.openPack == nil)
        #expect(grid.highlighted == packTile.word)
    }

    /// Sections of 5 and 3 laid out 3 wide: rows [0 1 2] [3 4] | [5 6 7].
    @Test func arrowsKeepTheColumnAcrossSections() {
        let counts = [5, 3]
        func go(_ move: IconGridNavigation.Move, _ from: Int) -> Int {
            IconGridNavigation.index(after: move, from: from, counts: counts, columns: 3)
        }
        #expect(go(.right, 4) == 5 && go(.left, 5) == 4 && go(.left, 0) == 0 && go(.right, 7) == 7)
        #expect(go(.down, 1) == 4)          // into the short last row
        #expect(go(.down, 2) == 4)          // no cell below: the row's last
        #expect(go(.down, 4) == 6)          // into the next section, same column
        #expect(go(.down, 3) == 5)
        #expect(go(.up, 6) == 4)            // back into the last row above
        #expect(go(.up, 7) == 4)            // that row is short: its last
        #expect(go(.up, 4) == 1 && go(.up, 1) == 1 && go(.down, 6) == 6)
        #expect(IconGridNavigation.index(after: .down, from: 0, counts: [2, 0, 2], columns: 2) == 2)
    }

    @Test func columnsFitTheWidth() {
        #expect(IconGridNavigation.columns(width: 500, cell: 92, spacing: 8) == 5)
        #expect(IconGridNavigation.columns(width: 50, cell: 92, spacing: 8) == 1)
    }

    @Test func addedFilesGetSafeUniqueNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("icons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("in")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("My Icon!.PNG")
        try Data([1]).write(to: file)
        let folder = dir.appendingPathComponent("icons")
        #expect(IconGridModel.copy([file], into: folder) == ["my-icon-"])
        #expect(IconGridModel.copy([file], into: folder) == ["my-icon--2"])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("my-icon--2.png").path))
        #expect(!IconGridModel.isPicture(URL(fileURLWithPath: "/x/a.txt")))
    }

    /// The thumbnail is made at the size asked for, from the image of the file nearest above it, not the whole picture.
    @Test func thumbnailIsMadeAtTheAskedSize() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("icon-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 512, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: file)
        let image = try #require(await IconThumbnails.shared.thumbnail(of: file, pixels: 64))
        #expect(image.width == 64 && image.height == 32)
        #expect(await IconThumbnails.shared.thumbnail(of: URL(fileURLWithPath: "/nonexistent.png"), pixels: 64) == nil)
    }
}

@MainActor
struct WellStateTests {
    private func gray(_ white: Double) -> Color { Color(.sRGB, red: white, green: white, blue: white, opacity: 1) }
    private func hex(_ color: Color) -> String { ColorText.hex(color) }

    @Test func wellFollowsStoreAfterEditCommitAndOutsideChange() {
        let store = MemoryStore(values: ["c": "#333333"])
        let model = SettingsModel(store: store)
        model.register([page([.color("c", "C")])])
        var state = WellState()
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#333333")

        // Dragging: the well shows the dragged colour although the store still has the old one.
        state.edit(gray(0.6))
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#999999")
        // An outside change while the change waits does not take the well away.
        state.storeChanged(hasPending: true)
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#999999")

        // The commit writes and hands the well back to the store.
        ColorWell.commit(gray(0.6), model: model, key: "c", index: 0, count: 1)
        state.committed()
        #expect(store.values["c"] == "#999999")
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#999999")

        // Typed value, Reset to Default, outside edit: the well shows the new stored colour.
        store.changeExternally(["c": "#112233"])
        state.storeChanged(hasPending: false)
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#112233")
        model.set("c", "#ff0000")
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#ff0000")
    }

    @Test func storeChangeWithNothingPendingDropsTheLocalColour() {
        var state = WellState()
        state.edit(gray(0.6))
        state.storeChanged(hasPending: false)
        #expect(state.local == nil)
        #expect(hex(state.displayed(text: "#112233", index: 0)) == "#112233")
    }

    @Test func rejectedCommitShowsTheStoredColour() {
        let store = MemoryStore(values: ["c": "#333333"], validate: { v, _ in v == "#999999" ? "Not allowed" : nil })
        let model = SettingsModel(store: store)
        model.register([page([.color("c", "C")])])
        var state = WellState()
        state.edit(gray(0.6))
        ColorWell.commit(gray(0.6), model: model, key: "c", index: 0, count: 1)
        state.committed()
        #expect(model.errors["c"] == "Not allowed")
        #expect(store.values["c"] == "#333333")
        #expect(hex(state.displayed(text: model.value("c"), index: 0)) == "#333333")
    }

    @Test func secondWellShowsNeutralGreyForMissingPart() {
        #expect(hex(ColorText.well("#333333", index: 1)) == "#808080")
        #expect(hex(ColorText.well("#333333,oops", index: 1)) == "#808080")
        #expect(hex(ColorText.well("#333333,#666", index: 1)) == "#666666")
    }
}
