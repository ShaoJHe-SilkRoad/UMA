import AppKit

@main
enum UMASafariBridgeHostMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = UMASafariBridgeHostApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        application.run()
        _ = delegate
    }
}
