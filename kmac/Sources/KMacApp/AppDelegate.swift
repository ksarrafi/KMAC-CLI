import AppKit
import SwiftUI

/// Borderless panel that can still become key, so the search field accepts input.
final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let health = HealthStore()
    private let input = PanelInput()
    private var statusItem: NSStatusItem?
    private var panel: SpotlightPanel?
    private var fixesWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar accessory: no Dock icon, stays resident.
        NSApp.setActivationPolicy(.accessory)

        health.startPolling()
        setupStatusItem()
        registerHotkey()
        registerURLHandler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        health.stopPolling()
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    /// Re-launching KMac while it's already running (e.g. picking it from
    /// Spotlight or the Dock) opens the ⌘K panel instead of doing nothing.
    /// This is how "⌘Space → kmac → Enter" surfaces the search panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel()
        return true
    }

    /// First launch from Spotlight (no prior instance): also show the panel,
    /// not just the menu-bar icon.
    func applicationDidBecomeActive(_ notification: Notification) {
        if panel == nil { showPanel() }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "KMac")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open KMac  (⌘K)", action: #selector(menuToggle), keyEquivalent: "")
        menu.addItem(withTitle: "Issues & Fixes…", action: #selector(openFixes), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit KMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.statusItem = item
    }

    @objc private func refreshNow() {
        Task { await health.refresh() }
    }

    // MARK: - Auxiliary windows

    @objc private func openFixes() {
        if fixesWindow == nil {
            fixesWindow = makeWindow(title: "KMac — Issues & Fixes",
                                     content: FixesView(health: health))
        }
        present(fixesWindow)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "KMac — Settings",
                                        content: SettingsView(health: health))
        }
        present(settingsWindow)
    }

    private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        // ⌘K from anywhere (requires Accessibility permission for global keyDown).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command), event.keyCode == 40 { // K
                Task { @MainActor in self?.showPanel() }
            }
        }
        // When our panel is focused: ⌘K toggles, Esc hides.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command), event.keyCode == 40 {
                self.togglePanel(); return nil
            }
            if event.keyCode == 53 { // Esc
                self.hidePanel(); return nil
            }
            return event
        }
    }

    // MARK: - URL scheme (kmac://ask?q=…)

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString)
        else { return }
        handle(url: url)
    }

    /// Parses `kmac://ask?q=<question>`, shows the panel, and injects the
    /// question so SpotlightView auto-submits it.
    private func handle(url: URL) {
        guard url.scheme == "kmac" else { return }
        showPanel()

        // Accept the question from either the host or the path: kmac://ask?q=…
        let isAsk = url.host == "ask" || url.path.contains("ask")
        guard isAsk else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let question = components?.queryItems?.first(where: { $0.name == "q" })?.value
        if let question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            input.submit(question)
        }
    }

    // MARK: - Panel

    @objc private func menuToggle() { togglePanel() }

    private func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> SpotlightPanel {
        let view = SpotlightView(health: health, input: input, onClose: { [weak self] in self?.hidePanel() })
        let hosting = NSHostingView(rootView: view)

        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = hosting
        return panel
    }
}
