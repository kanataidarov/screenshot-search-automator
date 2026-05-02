import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusItem: NSStatusItem?
    private let quickPromptsSettings = QuickPromptsSettingsController()
    private let hotKeySettings        = HotKeySettingsController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let appState = AppState()
        self.appState = appState
        setupStatusItem()

        do {
            try appState.start()
        } catch {
            appState.presentMessage(
                title: "Startup Error",
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    @objc
    private func openQuickPromptsSettings() {
        quickPromptsSettings.show()
    }

    @objc
    private func openHotKeySettings() {
        hotKeySettings.show()
    }

    @objc
    private func beginCaptureFlow() {
        appState?.beginCaptureFlow()
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func makeStatusBarIcon() -> NSImage? {
        guard let viewfinder = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Screenshot Search"),
              let magnifier  = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) else {
            return nil
        }
        let size = NSSize(width: 18, height: 18)
        let composite = NSImage(size: size, flipped: false) { rect in
            viewfinder.draw(in: rect)
            let magSize: CGFloat = 8
            let magRect = NSRect(
                x: (rect.width  - magSize) / 2,
                y: (rect.height - magSize) / 2,
                width: magSize,
                height: magSize
            )
            magnifier.draw(in: magRect)
            return true
        }
        composite.isTemplate = true
        return composite
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        if let button = statusItem.button {
            button.image = makeStatusBarIcon()
        }
        menu.addItem(NSMenuItem(title: "Capture", action: #selector(beginCaptureFlow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quick Prompts...", action: #selector(openQuickPromptsSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hotkey...", action: #selector(openHotKeySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q"))

        statusItem.menu = menu
        self.statusItem = statusItem
    }
}