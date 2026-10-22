import Testing
import AppKit
@testable import SettingsKit

struct WindowPlacementTests {
    private let main = NSRect(x: 0, y: 25, width: 1440, height: 875)
    private let side = NSRect(x: 1440, y: 0, width: 1920, height: 1055)

    @Test func savedFrameOnTheScreenIsKept() {
        let saved = NSRect(x: 100, y: 200, width: 782, height: 637)
        #expect(SettingsWindowPlacement.frame(saved: saved, in: main) == saved)
    }

    @Test func savedFrameOnAnotherScreenIsCentred() {
        let saved = NSRect(x: 1600, y: 100, width: 782, height: 637)
        let frame = SettingsWindowPlacement.frame(saved: saved, in: main)
        #expect(frame.size == saved.size)
        #expect(frame.midX == main.midX && frame.midY == main.midY)
        #expect(main.contains(frame))
    }

    @Test func sizeIsClampedToTheScreen() {
        let saved = NSRect(x: 1500, y: 0, width: 1800, height: 1000)
        let frame = SettingsWindowPlacement.frame(saved: saved, in: main)
        #expect(frame == NSRect(x: 0, y: 25, width: 1440, height: 875))
    }

    @Test func movesBetweenScreensBothWays() {
        let onMain = NSRect(x: 300, y: 100, width: 782, height: 637)
        let moved = SettingsWindowPlacement.frame(saved: onMain, in: side)
        #expect(side.contains(moved) && moved.size == onMain.size)
        #expect(SettingsWindowPlacement.frame(saved: moved, in: side) == moved)
    }
}
