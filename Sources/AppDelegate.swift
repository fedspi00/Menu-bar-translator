import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private let store = Store()
    private let loginItem = LoginItem()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var keyMonitor: Any?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setUpStatusItem()
        setUpPopover()

        store.onHotKeyPreferenceChange = { [weak self] enabled in
            self?.updateHotKey(enabled: enabled)
        }
        updateHotKey(enabled: store.hotKeyEnabled)
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeKeyMonitor()
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let symbol = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Translate")
            ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "Translate")
        if let symbol {
            symbol.isTemplate = true
            button.image = symbol
        } else {
            button.title = "文"
        }

        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Lingo — translate (⌥⌘T)"
    }

    @objc private func statusItemClicked() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            closePanel()
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Lingo", action: #selector(togglePanel), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lingo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    // MARK: - Panel

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 372)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(store: store, loginItem: loginItem)
        )
    }

    @objc private func togglePanel() {
        if popover.isShown {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem.button else { return }

        loginItem.refresh()
        store.panelDidOpen()

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        installKeyMonitor()
    }

    private func closePanel() {
        popover.performClose(nil)
        removeKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
    }

    // MARK: - Keyboard shortcuts inside the panel

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // esc — close
        if event.keyCode == 53 && modifiers.isEmpty {
            closePanel()
            return true
        }
        // ⌘⏎ — translate now
        if command && (event.keyCode == 36 || event.keyCode == 76) {
            store.translateNow()
            return true
        }
        guard command else { return false }

        switch (key, shift) {
        case ("c", true):
            store.copyOutput()
            return true
        case ("v", true):
            store.pasteAndTranslate()
            return true
        case ("k", false):
            store.clear()
            return true
        case ("s", false):
            store.swapLanguages()
            return true
        default:
            return false
        }
    }

    // MARK: - Global shortcut

    private func updateHotKey(enabled: Bool) {
        hotKey = nil
        guard enabled else { return }
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            self?.togglePanel()
        }
    }
}

/// "Open at login", backed by the modern ServiceManagement API.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        refresh()
    }
}
