import AppKit
import SwiftUI

@MainActor
final class QuickPromptsSettingsController {
    private var window: NSWindow?

    func show() {
        // Re-create each time so the view reflects the latest saved prompts.
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        window = makeWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let view = QuickPromptsSettingsView(
            prompts: PromptStore.shared.prompts,
            onSave: { [weak self] newPrompts in
                PromptStore.shared.save(newPrompts)
                self?.window?.close()
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Quick Prompts"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        return win
    }
}

struct QuickPromptsSettingsView: View {
    @State private var prompts: [String]
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    init(prompts: [String], onSave: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        _prompts = State(initialValue: prompts)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Prompts")
                .font(.title2.bold())

            Text("Assign a saved prompt to each numbered button. Leave empty to hide a button.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(width: 30, height: 30)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .padding(.top, 3)

                        TextField("Not set", text: $prompts[i], axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(prompts) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
