import AppKit
import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

/// The Settings window's frame is the user's. Installing the starting view
/// collapsed the window (released builds saved a 32 x 76 frame), and that size
/// then outlived the real content.
@Suite("Settings window frame", .serialized)
@MainActor
struct SettingsWindowFrameTests {
    private let minimum = SettingsWindowController.Layout.minimumSize

    private func autosaveName() -> String {
        "AUV.SettingsWindowFrameTests.\(UUID().uuidString)"
    }

    private func forget(_ name: String) {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(name)")
    }

    @Test("A new window opens at its default size, not collapsed to its minimum")
    func newWindowKeepsDefaultSize() throws {
        let name = autosaveName()
        defer { forget(name) }
        let controller = SettingsWindowController(autosaveName: name)
        defer { controller.tearDown() }
        let window = try #require(controller.window)
        let expected = window.frameRect(
            forContentRect: SettingsWindowController.Layout.defaultFrame
        ).size
        #expect(window.frame.size == expected)
        #expect(window.frame.size != minimum)
    }

    @Test("A restored frame below the minimum is replaced by the default size, in place")
    func undersizedFrameIsReplaced() {
        let fallback = NSRect(x: 0, y: 0, width: 640, height: 492)
        // The frame the installed 0.17.7 had saved.
        let saved = NSRect(x: 415, y: 731, width: 32, height: 76)
        let restored = SettingsWindowController.restorableFrame(saved, minimum: minimum, fallback: fallback)
        #expect(restored.size == fallback.size)
        #expect(restored.minX == saved.minX)
        #expect(restored.maxY == saved.maxY)
        // One dimension short is enough to be refused.
        let narrow = NSRect(x: 10, y: 10, width: 300, height: 600)
        #expect(SettingsWindowController.restorableFrame(narrow, minimum: minimum, fallback: fallback).size == fallback.size)
        // A frame the user could have chosen is kept exactly.
        let chosen = NSRect(x: 10, y: 10, width: 700, height: 520)
        #expect(SettingsWindowController.restorableFrame(chosen, minimum: minimum, fallback: fallback) == chosen)
    }

    @Test("A saved frame at or above the minimum is restored as saved")
    func reasonableSavedFrameIsKept() throws {
        let name = autosaveName()
        defer { forget(name) }
        UserDefaults.standard.set("200 200 700 520 0 0 1470 923 ", forKey: "NSWindow Frame \(name)")

        let controller = SettingsWindowController(autosaveName: name)
        defer { controller.tearDown() }
        let frame = try #require(controller.window?.frame)
        #expect(frame.size == NSSize(width: 700, height: 520))
    }

    @Test("Attaching content and opening every pane leave the frame where it was")
    func contentDoesNotResizeTheWindow() throws {
        let name = autosaveName()
        defer { forget(name) }
        let controller = SettingsWindowController(autosaveName: name)
        defer { controller.tearDown() }
        let window = try #require(controller.window)
        let chosen = NSRect(x: 220, y: 180, width: 640, height: 460)
        window.setFrame(chosen, display: false)

        controller.attach(store: UsageStore.preview(language: .english), preferences: .inMemory())
        #expect(window.frame.size == chosen.size)

        controller.showCanonicalWindow()
        for pane in GlobalSettingsPane.allCases {
            controller.selectPaneForTesting(pane)
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            #expect(window.frame.size == chosen.size, "pane \(pane.rawValue)")
        }
        controller.closeCanonicalWindow()
    }
}
