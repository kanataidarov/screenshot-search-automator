import AppKit

@MainActor
final class SelectionOverlayController {
    private let onSelection: (CGRect) -> Void
    private let onCancel: () -> Void
    private var windows: [OverlayWindow] = []
    private var trackingViews: [SelectionTrackingView] = []
    private var dragStartPoint: CGPoint?
    private var currentSelectionRect: CGRect?
    private var isShown = false

    init(onSelection: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onSelection = onSelection
        self.onCancel = onCancel
        configureWindows()
    }

    func show() {
        guard !isShown else {
            return
        }

        isShown = true
        NSCursor.crosshair.push()
        let mouseLocation = NSEvent.mouseLocation
        let primaryIndex = windows.firstIndex(where: { $0.frame.contains(mouseLocation) }) ?? 0

        for (index, window) in windows.enumerated() {
            if index == primaryIndex {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(trackingViews[index])
            } else {
                window.orderFrontRegardless()
            }
            window.invalidateCursorRects(for: trackingViews[index])
        }
        NSCursor.crosshair.set()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard isShown else {
            return
        }

        isShown = false
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        dragStartPoint = nil
        currentSelectionRect = nil
    }

    private func configureWindows() {
        let overlays = NSScreen.screens.map { screen in
            makeOverlay(for: screen)
        }

        windows = overlays.map(\.window)
        trackingViews = overlays.map(\.view)
    }

    private func makeOverlay(for screen: NSScreen) -> (window: OverlayWindow, view: SelectionTrackingView) {
        let screenFrame = screen.frame
        let view = SelectionTrackingView(frame: CGRect(origin: .zero, size: screenFrame.size), screenFrame: screenFrame)
        // Create with zero origin, then setFrame to the actual global position.
        // Passing screen.frame directly as contentRect with the screen: parameter
        // can cause the window to be placed at a double-offset on secondary displays.
        let window = OverlayWindow(
            contentRect: NSRect(origin: .zero, size: screenFrame.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.setFrame(screenFrame, display: false)

        view.dragBegan = { [weak self] point in
            self?.beginSelection(at: point)
        }
        view.dragChanged = { [weak self] point in
            self?.updateSelection(to: point)
        }
        view.dragEnded = { [weak self] point in
            self?.finishSelection(at: point)
        }
        view.cancelHandler = { [weak self] in
            self?.cancelSelection()
        }

        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.acceptsMouseMovedEvents = true

        return (window, view)
    }

    private func beginSelection(at point: CGPoint) {
        dragStartPoint = point
        currentSelectionRect = CGRect(origin: point, size: .zero)
        syncSelectionRect()
    }

    private func updateSelection(to point: CGPoint) {
        guard let dragStartPoint else {
            return
        }

        currentSelectionRect = CGRect(
            x: min(dragStartPoint.x, point.x),
            y: min(dragStartPoint.y, point.y),
            width: abs(point.x - dragStartPoint.x),
            height: abs(point.y - dragStartPoint.y)
        )
        syncSelectionRect()
    }

    private func finishSelection(at point: CGPoint) {
        updateSelection(to: point)

        guard let selectionRect = currentSelectionRect?.standardized,
              selectionRect.width >= 12,
              selectionRect.height >= 12 else {
            cancelSelection()
            return
        }

        close()
        onSelection(selectionRect)
    }

    private func cancelSelection() {
        close()
        onCancel()
    }

    private func syncSelectionRect() {
        trackingViews.forEach { view in
            view.selectionRect = currentSelectionRect
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionTrackingView: NSView {
    let screenFrame: CGRect

    var dragBegan: ((CGPoint) -> Void)?
    var dragChanged: ((CGPoint) -> Void)?
    var dragEnded: ((CGPoint) -> Void)?
    var cancelHandler: (() -> Void)?

    var selectionRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    init(frame frameRect: NSRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        addCrosshairTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addCrosshairTrackingArea()
    }

    private func addCrosshairTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        dragBegan?(globalPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        dragChanged?(globalPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        dragEnded?(globalPoint(for: event))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelHandler?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let overlayPath = NSBezierPath(rect: bounds)

        if let localSelectionRect {
            overlayPath.append(NSBezierPath(rect: localSelectionRect))
            overlayPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.22).setFill()
        overlayPath.fill()

        if let localSelectionRect {
            let rect = localSelectionRect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.92).setStroke()
            path.stroke()
        }
    }

    private var localSelectionRect: CGRect? {
        guard let selectionRect else {
            return nil
        }

        let localRect = CGRect(
            x: selectionRect.minX - screenFrame.minX,
            y: selectionRect.minY - screenFrame.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )
        let clippedRect = bounds.intersection(localRect.standardized)
        if clippedRect.isNull || clippedRect.isEmpty {
            return nil
        }
        return clippedRect
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(x: screenFrame.minX + localPoint.x, y: screenFrame.minY + localPoint.y)
    }
}