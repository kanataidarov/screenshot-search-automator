import AppKit
import Carbon
import SwiftUI

// MARK: - Window Controller

@MainActor
final class HotKeySettingsController {
    private var window: NSWindow?

    func show() {
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = makeWindow()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let vc = NSHostingController(rootView: HotKeySettingsView(
            onSave: { [weak self] keyCode, modifiers in
                HotKeyStore.shared.save(keyCode: keyCode, modifiers: modifiers)
                NotificationCenter.default.post(name: .hotKeyDidChange, object: nil)
                self?.window?.close()
            },
            onCancel: { [weak self] in self?.window?.close() }
        ))
        let w = NSWindow(contentViewController: vc)
        w.title = "Capture Hotkey"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }
}

// MARK: - SwiftUI View

struct HotKeySettingsView: View {
    let onSave:   (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    @State private var keyCode:     UInt32 = HotKeyStore.shared.keyCode
    @State private var modifiers:   UInt32 = HotKeyStore.shared.modifiers
    @State private var isRecording: Bool   = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Capture Hotkey")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Global shortcut")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                KeyRecorderView(keyCode: $keyCode, modifiers: $modifiers, isRecording: $isRecording)
                    .frame(maxWidth: .infinity, minHeight: 32)

                Text("Click the field, then press a new key combination.\nRequires ⌘ or ⌃. Press Esc to cancel recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") { onSave(keyCode, modifiers) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRecording)
            }
        }
        .frame(width: 300)
        .padding(24)
    }
}

// MARK: - NSViewRepresentable wrapper

struct KeyRecorderView: NSViewRepresentable {
    @Binding var keyCode:    UInt32
    @Binding var modifiers:  UInt32
    @Binding var isRecording: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let v = KeyRecorderNSView()
        v.coordinator = context.coordinator
        return v
    }

    func updateNSView(_ view: KeyRecorderNSView, context: Context) {
        view.setDisplay(keyCode: keyCode, modifiers: modifiers, isRecording: isRecording)
    }

    @MainActor
    final class Coordinator {
        var parent: KeyRecorderView
        init(_ p: KeyRecorderView) { self.parent = p }

        func didBeginRecording() { parent.isRecording = true }
        func didRecord(keyCode: UInt32, modifiers: UInt32) {
            parent.keyCode    = keyCode
            parent.modifiers  = modifiers
            parent.isRecording = false
        }
        func didCancelRecording() { parent.isRecording = false }
    }
}

// MARK: - Key recorder NSView

@MainActor
final class KeyRecorderNSView: NSView {
    weak var coordinator: KeyRecorderView.Coordinator?

    private var currentKeyCode:   UInt32 = HotKeyStore.defaultKeyCode
    private var currentModifiers: UInt32 = HotKeyStore.defaultModifiers
    private var recording        = false
    private var displayLabel     = HotKeyStore.describe(
        keyCode:   HotKeyStore.defaultKeyCode,
        modifiers: HotKeyStore.defaultModifiers
    )

    // Pure-modifier key codes (pressing these alone should not end recording)
    private static let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 6, yRadius: 6
        )

        if recording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        let isFocused = window?.firstResponder === self
        let borderColor: NSColor = isFocused ? .controlAccentColor : .separatorColor
        borderColor.setStroke()
        path.lineWidth = isFocused ? 2 : 1
        path.stroke()

        let label: String
        let color: NSColor
        if recording {
            label = "Press a key combination…"
            color = .placeholderTextColor
        } else {
            label = displayLabel
            color = .labelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let str  = NSAttributedString(string: label, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(
            x: (bounds.width  - size.width)  / 2,
            y: (bounds.height - size.height) / 2
        ))
    }

    // MARK: Focus

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        recording = true
        coordinator?.didBeginRecording()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        if recording {
            recording = false
            coordinator?.didCancelRecording()
        }
        needsDisplay = true
        return true
    }

    // MARK: Key capture

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }

        // Ignore bare modifier presses
        guard !Self.modifierOnlyCodes.contains(event.keyCode) else { return }

        // Escape = cancel
        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        // Require at least ⌘ or ⌃
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else {
            NSSound.beep()
            return
        }

        let newKeyCode   = UInt32(event.keyCode)
        let newModifiers = carbonModifiers(from: flags)

        currentKeyCode   = newKeyCode
        currentModifiers = newModifiers
        displayLabel     = HotKeyStore.describe(keyCode: newKeyCode, modifiers: newModifiers)

        recording = false
        coordinator?.didRecord(keyCode: newKeyCode, modifiers: newModifiers)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    // MARK: External update

    func setDisplay(keyCode: UInt32, modifiers: UInt32, isRecording: Bool) {
        currentKeyCode   = keyCode
        currentModifiers = modifiers
        recording        = isRecording
        displayLabel     = HotKeyStore.describe(keyCode: keyCode, modifiers: modifiers)
        needsDisplay     = true
    }

    // MARK: Helpers

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey)     }
        if flags.contains(.shift)   { result |= UInt32(shiftKey)   }
        if flags.contains(.option)  { result |= UInt32(optionKey)  }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
