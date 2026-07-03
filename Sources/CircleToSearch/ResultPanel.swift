import AppKit

@MainActor
final class ResultPanel: NSObject {
    private var panel: NSPanel?
    private var textView: NSTextView?
    private var hasButton = false
    private var action: (() -> Void)?

    func showLoading() {
        show(text: "Thinking…", actionTitle: nil, action: nil)
    }

    func showText(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        if panel != nil, actionTitle == nil, !hasButton {
            if let textView {
                textView.string = text
                Self.detectLinks(in: textView)
            }
        } else {
            show(text: text, actionTitle: actionTitle, action: action)
        }
    }

    private func show(text: String, actionTitle: String?, action: (() -> Void)?) {
        panel?.close()
        self.action = action
        self.hasButton = actionTitle != nil

        let width: CGFloat = 420
        let height: CGFloat = 260
        let mouse = NSEvent.mouseLocation
        let origin = NSPoint(x: mouse.x - width / 2, y: mouse.y - height - 20)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Circle to Search"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        Self.detectLinks(in: textView)

        let buttonArea: CGFloat = actionTitle != nil ? 48 : 0
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.frame = NSRect(x: 0, y: buttonArea, width: width, height: height - buttonArea)
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)

        if let actionTitle {
            let button = NSButton(title: actionTitle, target: self, action: #selector(runAction))
            button.bezelStyle = .rounded
            button.sizeToFit()
            button.setFrameOrigin(NSPoint(
                x: (width - button.frame.width) / 2,
                y: (buttonArea - button.frame.height) / 2
            ))
            button.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            container.addSubview(button)
        }

        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.textView = textView
    }

    @objc private func runAction() {
        action?()
    }

    /// Turns plain-text URLs into clickable links.
    private static func detectLinks(in textView: NSTextView) {
        textView.isEditable = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.checkTextInDocument(nil)
        textView.isEditable = false
    }
}
