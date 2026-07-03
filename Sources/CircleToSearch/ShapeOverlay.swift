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
        view.wantsLayer = true // needed for the sparkle emitter
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
    private var emitter: CAEmitterLayer?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()

        guard points.count > 1 else { return }
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }

        // Outer aura — wide, heavily blurred purple halo
        NSGraphicsContext.saveGraphicsState()
        let aura = NSShadow()
        aura.shadowBlurRadius = 18
        aura.shadowColor = NSColor.systemPurple
        aura.set()
        NSColor.systemPurple.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 9
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Inner glow — tighter cyan halo
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowBlurRadius = 8
        glow.shadowColor = NSColor.systemTeal
        glow.set()
        NSColor.systemTeal.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 4.5
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Bright white core
        NSColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        points = [point]
        startSparkles(at: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        points.append(point)
        emitter?.emitterPosition = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        emitter?.birthRate = 0
        let rect = ShapeMath.boundingBox(of: points, padding: 8, clampedTo: bounds)
        points = []
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            emitter?.birthRate = 0
            points = []
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Sparkles

    private func startSparkles(at point: CGPoint) {
        if emitter == nil, let layer {
            let newEmitter = Self.makeEmitter()
            layer.addSublayer(newEmitter)
            emitter = newEmitter
        }
        emitter?.emitterPosition = point
        emitter?.birthRate = 1
    }

    private static let sparkleImage: CGImage? = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        ("✦" as NSString).draw(
            at: NSPoint(x: 1, y: 0),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.white,
            ]
        )
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }()

    private static func makeEmitter() -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        emitter.birthRate = 0

        let cell = CAEmitterCell()
        cell.contents = sparkleImage
        cell.birthRate = 90
        cell.lifetime = 0.7
        cell.lifetimeRange = 0.3
        cell.velocity = 35
        cell.velocityRange = 25
        cell.emissionRange = .pi * 2
        cell.scale = 0.55
        cell.scaleRange = 0.35
        cell.scaleSpeed = -0.8
        cell.alphaSpeed = -1.4
        cell.spin = 3
        cell.spinRange = 6
        cell.color = NSColor.white.cgColor
        emitter.emitterCells = [cell]
        return emitter
    }
}
