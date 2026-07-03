import AppKit

@MainActor
final class ShapeOverlay {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    /// Shows the draw overlay on the screen under the mouse.
    /// completion receives the bounding rect in top-left-origin global
    /// coordinates (the format `screencapture -R` expects), or nil on cancel.
    func begin(completion: @escaping (CGRect?) -> Void) {
        guard window == nil else { return } // already active

        self.completion = completion
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main!

        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.acceptsMouseMovedEvents = true

        let view = DrawView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rectInView in
            self?.finish(rectInView: rectInView)
        }
        window.contentView = view

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(view)
        NSCursor.crosshair.push()

        self.window = window
    }

    private func finish(rectInView: CGRect?) {
        var globalRect: CGRect?
        if let rect = rectInView, let window {
            let screenRect = window.convertToScreen(rect) // bottom-left-origin global
            let primaryHeight = NSScreen.screens[0].frame.height
            globalRect = CGRect(
                x: screenRect.origin.x,
                y: primaryHeight - screenRect.maxY, // flip to top-left origin
                width: screenRect.width,
                height: screenRect.height
            )
        }

        NSCursor.pop()
        window?.orderOut(nil)
        window = nil

        let done = completion
        completion = nil
        done?(globalRect)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class DrawView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var points: [CGPoint] = []

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        NSColor.systemBlue.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        points = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = ShapeMath.boundingBox(of: points, padding: 8, clampedTo: bounds)
        points = []
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            points = []
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
