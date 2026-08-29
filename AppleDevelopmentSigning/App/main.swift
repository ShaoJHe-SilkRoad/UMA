import AppKit

// This target exists only so Xcode can resolve automatic development signing
// for UMA's real containing-app identifier. The production executable remains
// the SwiftPM-built CodexUsageMonitor binary assembled by the package script.
_ = NSApplication.shared
