import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusItem: NSStatusItem?

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
    private func beginCaptureFlow() {
        appState?.beginCaptureFlow()
    }

    @objc
    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        statusItem.button?.title = "Shot"
        menu.addItem(NSMenuItem(title: "Capture", action: #selector(beginCaptureFlow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q"))

        statusItem.menu = menu
        self.statusItem = statusItem
    }
}