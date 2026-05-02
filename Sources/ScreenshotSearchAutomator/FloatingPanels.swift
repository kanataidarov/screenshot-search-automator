import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let panel: FloatingPanelWindow
    private let size: NSSize

    init(size: NSSize) {
        self.size = size
        self.panel = FloatingPanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
    }

    func show<Content: View>(relativeTo rect: CGRect, on screen: NSScreen, @ViewBuilder content: () -> Content) {
        panel.contentView = NSHostingView(rootView: content())
        panel.setFrame(NSRect(origin: panelOrigin(relativeTo: rect, on: screen), size: size), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel.orderOut(nil)
    }

    private func panelOrigin(relativeTo rect: CGRect, on screen: NSScreen) -> CGPoint {
        let visibleFrame = screen.visibleFrame.insetBy(dx: 16, dy: 16)

        var origin = CGPoint(
            x: rect.minX,
            y: rect.minY - size.height - 12
        )

        if origin.y < visibleFrame.minY {
            origin.y = rect.maxY + 12
        }

        if origin.x + size.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - size.width
        }

        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX
        }

        if origin.y + size.height > visibleFrame.maxY {
            origin.y = visibleFrame.maxY - size.height
        }

        if origin.y < visibleFrame.minY {
            origin.y = visibleFrame.minY
        }

        return origin
    }
}

private final class FloatingPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct QuestionPromptView: View {
    let prompts: [String]
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var question = ""
    @FocusState private var isFocused: Bool

    private var activePrompts: [(index: Int, text: String)] {
        prompts.enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { (index: $0.offset, text: $0.element) }
    }

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Ask about this screenshot")
                        .font(.headline)
                    Spacer()
                    if !activePrompts.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(activePrompts, id: \.index) { item in
                                Button {
                                    onSubmit(item.text)
                                } label: {
                                    Text("\(item.index + 1)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .frame(width: 26, height: 26)
                                }
                                .buttonStyle(.bordered)
                                .help(item.text)
                            }
                        }
                    }
                }

                TextField("What should the AI look at here?", text: $question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isFocused)

                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Button("Send") {
                        onSubmit(question.trimmed)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(question.trimmed.isEmpty)
                }
            }
            .frame(width: 420, alignment: .leading)
            .padding(18)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

struct ResponseBubbleView: View {
    let title: String
    let message: String
    let isLoading: Bool
    let isError: Bool
    let onClose: () -> Void
    let actionTitle: String?
    let onAction: (() -> Void)?

    init(
        title: String,
        message: String,
        isLoading: Bool,
        isError: Bool,
        onClose: @escaping () -> Void,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.isLoading = isLoading
        self.isError = isError
        self.onClose = onClose
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isError ? .red : .primary)
                    Spacer()
                    Button("Close", action: onClose)
                }

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        Text(message)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)

                    if let actionTitle, let onAction {
                        HStack {
                            Button(actionTitle, action: onAction)
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 420, alignment: .leading)
            .padding(18)
        }
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(1)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}