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
    private var statusItem: NSStatusItem?
    private var panel: SpotlightPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar accessory: no Dock icon, stays resident.
        NSApp.setActivationPolicy(.accessory)

        health.startPolling()
        setupStatusItem()
        registerHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        health.stopPolling()
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "KMac")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open KMac  (⌘K)", action: #selector(menuToggle), keyEquivalent: "")
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
        let view = SpotlightView(health: health, onClose: { [weak self] in self?.hidePanel() })
        let hosting = NSHostingView(rootView: view)

        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
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
