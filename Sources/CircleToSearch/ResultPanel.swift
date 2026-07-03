import AppKit

@MainActor
final class ResultPanel {
    private var panel: NSPanel?
    private var textView: NSTextView?

    func showLoading() {
        show(text: "Thinking…")
    }

    func showText(_ text: String) {
        if panel == nil {
            show(text: text)
        } else {
            textView?.string = text
        }
    }

    private func show(text: String) {
        panel?.close()

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

        panel.contentView = scrollView
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.textView = textView
    }
}
