import AppKit

@MainActor
final class ResultPanel: NSObject {
    private static let panelWidth: CGFloat = 460
    private static let panelHeight: CGFloat = 400

    private var panel: NSPanel?
    private var action: (() -> Void)?

    private final class LinkButton: NSButton {
        var url: URL?
    }

    // MARK: - Public API

    func showLoading() {
        present(makeTextContent(text: "✨ Thinking…", actionTitle: nil))
    }

    func showText(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        present(makeTextContent(text: text, actionTitle: actionTitle))
    }

    func showAnswer(_ answer: Answer, thumbnail: NSImage?) {
        present(makeAnswerContent(answer: answer, thumbnail: thumbnail))
    }

    // MARK: - Panel

    private func present(_ content: NSView) {
        // Reuse the existing panel's position (loading → answer transition);
        // otherwise open near the mouse.
        let size = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        let origin: NSPoint
        if let existing = panel, existing.isVisible {
            origin = existing.frame.origin
            existing.close()
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 20)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Circle to Search"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        content.frame = NSRect(origin: .zero, size: size)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    // MARK: - Answer layout

    private func makeAnswerContent(answer: Answer, thumbnail: NSImage?) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)

        if let thumbnail {
            let imageView = NSImageView(image: thumbnail)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 10
            imageView.layer?.masksToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true
            stack.addArrangedSubview(imageView)
        }

        let title = NSTextField(wrappingLabelWithString: answer.title)
        title.font = .boldSystemFont(ofSize: 15)
        stack.addArrangedSubview(title)

        if !answer.body.isEmpty {
            let body = NSTextField(wrappingLabelWithString: answer.body)
            body.font = .systemFont(ofSize: 13)
            stack.addArrangedSubview(body)
        }

        var chips: [NSView] = []
        if let address = answer.address, let url = mapsURL(for: address) {
            let maps = makeChip(title: "📍 Open in Maps", url: url)
            maps.keyEquivalent = "\r" // Enter opens Maps
            chips.append(maps)
        }
        for source in answer.sources.prefix(3) {
            let chip = makeChip(title: "🔗 " + shortTitle(source.title), url: source.url)
            loadFavicon(for: source, into: chip)
            chips.append(chip)
        }
        if !chips.isEmpty {
            let row = NSStackView(views: chips)
            row.orientation = .horizontal
            row.spacing = 8
            stack.addArrangedSubview(row)
        }

        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeChip(title: String, url: URL) -> LinkButton {
        let button = LinkButton(title: title, target: self, action: #selector(openLink(_:)))
        button.url = url
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.toolTip = url.absoluteString
        return button
    }

    /// Grounding titles are usually domains ("wikipedia.org"); shorten anything long.
    private func shortTitle(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "www.", with: "")
        return cleaned.count > 28 ? String(cleaned.prefix(25)) + "…" : cleaned
    }

    private func mapsURL(for address: String) -> URL? {
        guard let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }

    /// Best-effort favicon: grounding titles are typically bare domains.
    private func loadFavicon(for source: Answer.Source, into button: LinkButton) {
        let domain = source.title.contains(".") ? source.title : (source.url.host ?? "")
        guard !domain.isEmpty,
              let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32") else {
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor in
                image.size = NSSize(width: 14, height: 14)
                button.image = image
                button.imagePosition = .imageLeading
                button.title = button.title.replacingOccurrences(of: "🔗 ", with: "")
            }
        }.resume()
    }

    @objc private func openLink(_ sender: NSButton) {
        guard let url = (sender as? LinkButton)?.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Plain text layout (loading / errors)

    private func makeTextContent(text: String, actionTitle: String?) -> NSView {
        let size = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        let container = NSView(frame: NSRect(origin: .zero, size: size))

        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isEditable = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.checkTextInDocument(nil)
        textView.isEditable = false

        let buttonArea: CGFloat = actionTitle != nil ? 48 : 0
        scrollView.frame = NSRect(x: 0, y: buttonArea, width: size.width, height: size.height - buttonArea)
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)

        if let actionTitle {
            let button = NSButton(title: actionTitle, target: self, action: #selector(runAction))
            button.bezelStyle = .rounded
            button.sizeToFit()
            button.setFrameOrigin(NSPoint(
                x: (size.width - button.frame.width) / 2,
                y: (buttonArea - button.frame.height) / 2
            ))
            button.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
            container.addSubview(button)
        }
        return container
    }

    @objc private func runAction() {
        action?()
    }
}
