import AppKit
import Carbon
import Foundation

@MainActor
final class AppState {
    private let hotKeyCenter = HotKeyCenter()
    private let captureService = CaptureService()
    private let apiClient = APIClient(configuration: .load())

    private var selectionOverlay: SelectionOverlayController?
    private var promptPanel: FloatingPanelController?
    private var responsePanel: FloatingPanelController?
    private var activeSelection: CapturedSelection?

    func start() throws {
        hotKeyCenter.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.beginCaptureFlow()
            }
        }

        try hotKeyCenter.register(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | shiftKey))
    }

    func beginCaptureFlow() {
        dismissFloatingPanels()
        dismissSelectionOverlays()
        activeSelection = nil

        guard captureService.ensureScreenCaptureAccess() else {
            presentScreenCapturePermissionMessage()
            return
        }

        let overlay = SelectionOverlayController { [weak self] rect in
            self?.completeSelection(rect)
        } onCancel: { [weak self] in
            self?.dismissSelectionOverlays()
        }

        selectionOverlay = overlay
        overlay.show()
    }

    func presentMessage(title: String, message: String, isError: Bool) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        showMessagePanel(
            title: title,
            message: message,
            isError: isError,
            actionTitle: nil,
            action: nil,
            on: screen
        )
    }

    private func completeSelection(_ rect: CGRect) {
        dismissSelectionOverlays()

        let standardizedRect = rect.standardized
        guard standardizedRect.width >= 12, standardizedRect.height >= 12 else {
            return
        }

        guard let anchorScreen = screenContainingSelection(standardizedRect) else {
            presentMessage(
                title: "Selection Failed",
                message: "The selected area did not map to an active display.",
                isError: true
            )
            return
        }

        Task {
            do {
                let imageData = try await captureService.capturePNG(in: standardizedRect)
                let selection = CapturedSelection(screen: anchorScreen, rect: standardizedRect, imageData: imageData)
                activeSelection = selection
                showPrompt(for: selection)
            } catch {
                presentCaptureError(error)
            }
        }
    }

    private func presentCaptureError(_ error: Error) {
        if let captureError = error as? CaptureError, captureError == .permissionDenied {
            presentScreenCapturePermissionMessage()
            return
        }

        let nsError = error as NSError
        if nsError.localizedDescription.localizedCaseInsensitiveContains("declined TCCs") {
            presentScreenCapturePermissionMessage()
            return
        }

        presentMessage(
            title: "Capture Failed",
            message: error.localizedDescription,
            isError: true
        )
    }

    private func presentScreenCapturePermissionMessage() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        showMessagePanel(
            title: "Screen Recording Required",
            message: "macOS blocked screen capture for this app. Grant Screen Recording access in System Settings, then quit and reopen the app bundle before trying again.",
            isError: true,
            actionTitle: "Open Settings",
            action: { [weak self] in
                self?.openScreenRecordingSettings()
            },
            on: screen
        )
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func showPrompt(for selection: CapturedSelection) {
        dismissFloatingPanels()

        let panel = FloatingPanelController(size: NSSize(width: 460, height: 150))
        panel.show(relativeTo: selection.rect, on: selection.screen) {
            QuestionPromptView(
                onSubmit: { [weak self] question in
                    self?.submitQuestion(question)
                },
                onCancel: { [weak self] in
                    self?.dismissFloatingPanels()
                }
            )
        }
        promptPanel = panel
    }

    private func submitQuestion(_ question: String) {
        guard let selection = activeSelection else {
            return
        }

        promptPanel?.close()
        promptPanel = nil

        let loadingPanel = FloatingPanelController(size: NSSize(width: 460, height: 220))
        loadingPanel.show(relativeTo: selection.rect, on: selection.screen) {
            ResponseBubbleView(
                title: "Thinking",
                message: "Sending screenshot and prompt to the API...",
                isLoading: true,
                isError: false,
                onClose: { [weak self] in self?.dismissFloatingPanels() }
            )
        }
        responsePanel = loadingPanel

        Task {
            do {
                let answer = try await apiClient.ask(question: question, imageData: selection.imageData)
                showResponse(answer, for: selection, isError: false)
            } catch {
                showResponse(error.localizedDescription, for: selection, isError: true)
            }
        }
    }

    private func showResponse(_ message: String, for selection: CapturedSelection, isError: Bool) {
        responsePanel?.close()

        let panel = FloatingPanelController(size: NSSize(width: 460, height: 240))
        panel.show(relativeTo: selection.rect, on: selection.screen) {
            ResponseBubbleView(
                title: isError ? "Request Failed" : "Answer",
                message: message,
                isLoading: false,
                isError: isError,
                onClose: { [weak self] in self?.dismissFloatingPanels() }
            )
        }
        responsePanel = panel
    }

    private func showMessagePanel(
        title: String,
        message: String,
        isError: Bool,
        actionTitle: String?,
        action: (() -> Void)?,
        on screen: NSScreen
    ) {
        dismissFloatingPanels()

        let anchorRect = CGRect(
            x: screen.visibleFrame.midX - 140,
            y: screen.visibleFrame.midY - 20,
            width: 280,
            height: 40
        )

        let panel = FloatingPanelController(size: NSSize(width: 460, height: 220))
        panel.show(relativeTo: anchorRect, on: screen) {
            ResponseBubbleView(
                title: title,
                message: message,
                isLoading: false,
                isError: isError,
                onClose: { [weak self] in self?.dismissFloatingPanels() },
                actionTitle: actionTitle,
                onAction: action
            )
        }
        responsePanel = panel
    }

    private func dismissSelectionOverlays() {
        selectionOverlay?.close()
        selectionOverlay = nil
    }

    private func screenContainingSelection(_ rect: CGRect) -> NSScreen? {
        let matchingScreens = NSScreen.screens
            .map { screen in
                (screen, screen.frame.intersection(rect))
            }
            .filter { !$0.1.isNull && !$0.1.isEmpty }

        if let bestMatch = matchingScreens.max(by: { lhs, rhs in
            lhs.1.width * lhs.1.height < rhs.1.width * rhs.1.height
        })?.0 {
            return bestMatch
        }

        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { screen in
            screen.frame.contains(midpoint)
        }
    }

    private func dismissFloatingPanels() {
        promptPanel?.close()
        responsePanel?.close()
        promptPanel = nil
        responsePanel = nil
    }
}

@MainActor
struct CapturedSelection {
    let screen: NSScreen
    let rect: CGRect
    let imageData: Data
}