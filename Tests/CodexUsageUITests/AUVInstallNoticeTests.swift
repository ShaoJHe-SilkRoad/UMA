import CodexUsageUI
import Foundation
import Testing

@Suite("Install notice")
struct AUVInstallNoticeTests {
    @Test("Where AUV runs from decides the notice")
    func location() {
        let home = "/Users/someone"
        #expect(AUVInstallNotice.location(bundlePath: "/Applications/UMA.app", homeDirectory: home,
                                          isOnReadOnlyVolume: false) == .applications)
        #expect(AUVInstallNotice.location(bundlePath: "\(home)/Applications/UMA.app", homeDirectory: home,
                                          isOnReadOnlyVolume: false) == .applications)
        #expect(AUVInstallNotice.location(bundlePath: "/Volumes/AUV 0.18.9/UMA.app", homeDirectory: home,
                                          isOnReadOnlyVolume: true) == .diskImageOrTemporary)
        #expect(AUVInstallNotice.location(
            bundlePath: "/private/var/folders/x/T/AppTranslocation/ABC/d/UMA.app", homeDirectory: home,
            isOnReadOnlyVolume: false) == .diskImageOrTemporary)
        // A development build or a copy left in Downloads stays quiet.
        #expect(AUVInstallNotice.location(bundlePath: "\(home)/Downloads/UMA.app", homeDirectory: home,
                                          isOnReadOnlyVolume: false) == .elsewhere)
    }

    @Test("Installed is said once per build; not installed is said every time")
    func decide() {
        let key = "0.18.9 (2026111507)"
        #expect(AUVInstallNotice.decide(location: .applications, version: "0.18.9", versionKey: key,
                                        lastNoticedKey: nil) == .installed(version: "0.18.9"))
        #expect(AUVInstallNotice.decide(location: .applications, version: "0.18.9", versionKey: key,
                                        lastNoticedKey: "0.18.8 (2026111506)") == .installed(version: "0.18.9"))
        #expect(AUVInstallNotice.decide(location: .applications, version: "0.18.9", versionKey: key,
                                        lastNoticedKey: key) == nil)
        #expect(AUVInstallNotice.decide(location: .diskImageOrTemporary, version: "0.18.9", versionKey: key,
                                        lastNoticedKey: key) == .notInstalled)
        #expect(AUVInstallNotice.decide(location: .elsewhere, version: "0.18.9", versionKey: key,
                                        lastNoticedKey: nil) == nil)
    }

    @Test("Both notices read in both languages")
    func copy() {
        for language in [AppLanguage.english, .simplifiedChinese] {
            for notice in [AUVInstallNotice.installed(version: "0.18.9"), .notInstalled] {
                #expect(!notice.title(language).isEmpty)
                #expect(!notice.message(language, installerMounted: false).isEmpty)
            }
            #expect(AUVInstallNotice.installed(version: "0.18.9").message(language, installerMounted: true)
                .count > AUVInstallNotice.installed(version: "0.18.9").message(language, installerMounted: false).count)
        }
        #expect(AUVInstallNotice.installed(version: "0.18.9").title(.simplifiedChinese) == "AUV 0.18.9 已安装")
    }

    @Test("The notice is shown from the run loop, and Quit goes through the run loop")
    func presenterAvoidsMainQueueBlocks() throws {
        // A modal alert inside a main-queue block deadlocked Quit in build
        // 2026111507: termination waits for a main-actor task that cannot run.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/CodexUsageUI/Services/AUVInstallNotice.swift"),
            encoding: .utf8)
        #expect(!source.contains("DispatchQueue.main"))
        #expect(source.contains("RunLoop.main.add(timer, forMode: .common)"))
        #expect(!source.contains("NSApp.terminate(nil)"))
        #expect(source.contains("NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)"))
    }
}
