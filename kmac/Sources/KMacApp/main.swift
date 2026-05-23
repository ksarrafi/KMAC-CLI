import AppKit

// Plain AppKit bootstrap (no Info.plist needed): a resident menu-bar agent
// that opens a Cmd+K spotlight panel backed by the shared KMacCore engine.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
