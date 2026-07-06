import AppKit

@MainActor
final class ResultPanel: NSObject {
    private static let cardWidth: CGFloat = 420

    private var panel: NSPanel?
    private var action: (() -> Void)?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var loadingTimer: Timer?
    /// While a request is in flight the card is pinned: it floats on top and
    /// outside clicks pass through to other apps instead of dismissing it.
    /// Flipped on once the answer (or an error) is final.
    private var dismissesOnOutsideClick = false

    private static let loadingPhrases = [
        "🤠 Lassoing that in…",
        "🔍 Zooming… and enhancing…",
        "🌐 Galloping across the web…",
        "🕵️ Following the clues…",
        "🧠 Connecting the dots…",
        "📚 Cross-checking the facts…",
        "🎯 Narrowing it down…",
        "✨ Sprinkling AI dust on it…",
        "🗺 Asking around town…",
        "🤔 Hmm, seen this before…",
    ]

    private final class LinkButton: NSButton {
        var url: URL?
    }

    private final class FollowUpButton: NSButton {
        var question: String?
    }

    /// Called when the user taps a suggested follow-up question.
    var onFollowUp: ((String) -> Void)?

    private final class CardPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    // MARK: - Public API

    func showLoading() {
        dismissesOnOutsideClick = false // pin while searching
        var phrases = Self.loadingPhrases.shuffled()

        let label = NSTextField(labelWithString: phrases[0])
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor

        let stack = baseStack()
        stack.addArrangedSubview(label)
        present(stack)

        // Cycle through suspense phrases with a little fade until the answer
        // (or an error) replaces the card. present()/dismiss() clear the timer.
        var index = 0
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                index += 1
                if index == phrases.count { phrases.shuffle(); index = 0 }
                let phrase = phrases[index]
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    label.animator().alphaValue = 0
                }) {
                    label.stringValue = phrase
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        label.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    /// Instant on-device "first read" (OCR / barcodes) shown before the model
    /// answers. Stays pinned; the streamed answer replaces it in place.
    func showQuickRead(_ read: VisionRecognizer.QuickRead) {
        loadingTimer?.invalidate()
        loadingTimer = nil
        dismissesOnOutsideClick = false // still enriching — stay pinned

        let stack = baseStack()
        let contentWidth = Self.cardWidth - stack.edgeInsets.left - stack.edgeInsets.right

        let hint = NSTextField(labelWithString: "🔎  Identifying…")
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(8, after: hint)

        let body = NSTextField(wrappingLabelWithString: read.lines.joined(separator: "\n"))
        body.font = .systemFont(ofSize: 14)
        body.textColor = .labelColor
        body.isSelectable = true
        body.maximumNumberOfLines = 8
        body.lineBreakMode = .byTruncatingTail
        body.preferredMaxLayoutWidth = contentWidth
        stack.addArrangedSubview(body)

        render(stack, reuse: panel != nil)
    }

    /// Replaces the loading phrases with the model's live reasoning summary
    /// while it searches. Updates in place as new thoughts stream in.
    func showThinking(_ text: String) {
        loadingTimer?.invalidate() // real thoughts replace the canned phrases
        loadingTimer = nil
        dismissesOnOutsideClick = false // still searching — stay pinned

        let label = NSTextField(labelWithString: "🔎  \(text)")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        let stack = baseStack()
        stack.addArrangedSubview(label)
        render(stack, reuse: panel != nil)
    }

    func showText(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        dismissesOnOutsideClick = true // terminal message — clicking away dismisses
        present(makeMessageContent(text: text, actionTitle: actionTitle))
    }

    /// Called once the answer stream ends: unpins the card so an outside
    /// click dismisses it again.
    func finishStreaming() {
        dismissesOnOutsideClick = true
    }

    /// Renders (or updates, while streaming) the answer card. When a card is
    /// already on screen it is updated in place — no fade, no reposition — so
    /// progressive streaming updates don't flicker.
    func showAnswer(_ answer: Answer, thumbnail: NSImage?) {
        render(makeAnswerContent(answer: answer, thumbnail: thumbnail), reuse: panel != nil)
    }

    func dismiss() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
        loadingTimer?.invalidate()
        loadingTimer = nil
        panel?.close()
        panel = nil
    }

    // MARK: - Card presentation

    private func present(_ stack: NSStackView) {
        render(stack, reuse: false)
    }

    /// Builds the frosted-glass card around `stack`. The material is composited
    /// behind the window by the window server, so it must be clipped with
    /// maskImage — a plain layer cornerRadius leaves opaque corners outside the
    /// rounding.
    private func makeCard(around stack: NSStackView) -> NSVisualEffectView {
        let card = NSVisualEffectView()
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.maskImage = Self.roundedMask(radius: 18)
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: Self.cardWidth),
        ])
        return card
    }

    /// Shows `stack` in the card. `reuse: true` swaps the content of the
    /// existing panel in place (used for streaming updates); `reuse: false`
    /// tears down any old panel and fades a fresh one in.
    private func render(_ stack: NSStackView, reuse: Bool) {
        // Any real content ends the loading-phrase cycle.
        loadingTimer?.invalidate()
        loadingTimer = nil

        let card = makeCard(around: stack)
        let height = card.fittingSize.height
        let size = NSSize(width: Self.cardWidth, height: height)

        // In-place update: keep the panel, monitors and top edge; no fade.
        if reuse, let panel {
            let frame = panel.frame
            panel.contentView = card
            panel.setFrame(
                NSRect(x: frame.origin.x, y: frame.maxY - height, width: size.width, height: height),
                display: true
            )
            panel.invalidateShadow()
            return
        }

        let previousFrame = (panel?.isVisible == true) ? panel?.frame : nil
        dismiss()

        // Keep the top edge anchored on loading → answer transitions
        let origin: NSPoint
        if let previousFrame {
            origin = NSPoint(x: previousFrame.origin.x, y: previousFrame.maxY - height)
        } else {
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 24)
        }

        let panel = CardPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = card

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow() // recompute shadow against the rounded mask
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        // Click anywhere outside (other apps) or press Esc to dismiss — but
        // only once the search is done; while pinned, clicks pass through.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.dismissesOnOutsideClick else { return }
                self.dismiss()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor in self?.dismiss() }
                return nil
            }
            return event
        }
    }

    /// Stretchable rounded-rect mask for the visual effect material.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    // MARK: - Content builders

    private func baseStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        return stack
    }

    private func makeMessageContent(text: String, actionTitle: String? = nil) -> NSStackView {
        let stack = baseStack()

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.isSelectable = true
        stack.addArrangedSubview(label)

        if let actionTitle {
            let button = NSButton(title: actionTitle, target: self, action: #selector(runAction))
            button.bezelStyle = .rounded
            button.controlSize = .regular
            stack.addArrangedSubview(button)
        }
        return stack
    }

    private func makeAnswerContent(answer: Answer, thumbnail: NSImage?) -> NSStackView {
        let stack = baseStack()
        let contentWidth = Self.cardWidth - stack.edgeInsets.left - stack.edgeInsets.right

        if let thumbnail, thumbnail.size.width > 0 {
            let aspect = thumbnail.size.height / thumbnail.size.width
            let height = min(contentWidth * aspect, 130)
            let imageView = NSImageView(image: thumbnail)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 12
            imageView.layer?.masksToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: contentWidth),
                imageView.heightAnchor.constraint(equalToConstant: height),
            ])
            stack.addArrangedSubview(imageView)
        }

        let title = NSTextField(wrappingLabelWithString: answer.title)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .labelColor
        title.isSelectable = true
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(14, after: last)
        }
        stack.addArrangedSubview(title)
        stack.setCustomSpacing(6, after: title)

        if !answer.body.isEmpty {
            let body = NSTextField(wrappingLabelWithString: answer.body)
            body.font = .systemFont(ofSize: 13)
            body.textColor = .secondaryLabelColor
            body.isSelectable = true
            // a bit of line breathing room for the emoji fact lines
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            body.attributedStringValue = NSAttributedString(
                string: answer.body,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph,
                ]
            )
            stack.addArrangedSubview(body)
        }

        // Quick actions (model links, maps, shopping) on their own row; web
        // sources on a second row — a single row overflows the card.
        var actions: [NSView] = []
        for link in answer.links.prefix(2) {
            actions.append(makeChip(title: "🔗 \(link.title)", url: link.url))
        }
        if let address = answer.address, let url = mapsURL(for: address) {
            actions.append(makeChip(title: "📍 Open in Maps", url: url))
        }
        actions.append(contentsOf: actionChips(for: answer))

        var sources: [NSView] = []
        for source in answer.sources.prefix(3) {
            let chip = makeChip(title: shortTitle(source.title), url: source.url)
            loadFavicon(for: source, into: chip)
            sources.append(chip)
        }

        if !actions.isEmpty || !sources.isEmpty {
            addSeparator(to: stack)
            for chips in [actions, sources] where !chips.isEmpty {
                let row = NSStackView(views: chips)
                row.orientation = .horizontal
                row.spacing = 8
                stack.addArrangedSubview(row)
            }
        }

        if onFollowUp != nil {
            addSeparator(to: stack)
            for question in answer.followUps.prefix(3) {
                let card = makeFollowUpCard(question: question, width: contentWidth)
                stack.addArrangedSubview(card)
                stack.setCustomSpacing(6, after: card)
            }

            let field = NSTextField()
            field.placeholderString = "Ask anything about this…"
            field.font = .systemFont(ofSize: 12)
            field.bezelStyle = .roundedBezel
            field.focusRingType = .none
            field.target = self
            field.action = #selector(submitCustomQuestion(_:))
            (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            if let last = stack.arrangedSubviews.last {
                stack.setCustomSpacing(10, after: last)
            }
            stack.addArrangedSubview(field)
        }
        return stack
    }

    /// A tappable card row for a suggested follow-up question.
    private func makeFollowUpCard(question: String, width: CGFloat) -> NSView {
        let button = FollowUpButton(
            title: "✨  \(question)",
            target: self,
            action: #selector(askFollowUp(_:))
        )
        button.question = question
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.font = .systemFont(ofSize: 12)
        button.alignment = .left
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: width),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    private func addSeparator(to stack: NSStackView) {
        let line = NSBox()
        line.boxType = .separator
        if let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(12, after: last)
        }
        stack.addArrangedSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(
            equalToConstant: Self.cardWidth - stack.edgeInsets.left - stack.edgeInsets.right
        ).isActive = true
        stack.setCustomSpacing(12, after: line)
    }

    /// Deterministic quick actions derived from the answer's subject kind.
    /// Digital goods get none — you can't find software "nearby", and the
    /// source links already lead to it.
    private func actionChips(for answer: Answer) -> [NSView] {
        guard let query = answer.entityName
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        switch answer.kind {
        case .place:
            guard let destination = (answer.address ?? answer.entityName)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://maps.apple.com/?daddr=\(destination)") else { return [] }
            return [makeChip(title: "🗺 Directions", url: url)]
        case .product:
            var chips: [NSView] = []
            if let nearby = URL(string: "https://maps.apple.com/?q=\(query)") {
                chips.append(makeChip(title: "🛒 Find nearby", url: nearby))
            }
            if let shop = URL(string: "https://www.google.com/search?tbm=shop&q=\(query)") {
                chips.append(makeChip(title: "💰 Compare prices", url: shop))
            }
            return chips
        case .digital, .other:
            return []
        }
    }

    // MARK: - Chips

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
            }
        }.resume()
    }

    // MARK: - Actions

    @objc private func openLink(_ sender: NSButton) {
        guard let url = (sender as? LinkButton)?.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func runAction() {
        action?()
    }

    @objc private func askFollowUp(_ sender: NSButton) {
        guard let question = (sender as? FollowUpButton)?.question else { return }
        onFollowUp?(question)
    }

    @objc private func submitCustomQuestion(_ sender: NSTextField) {
        let question = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        onFollowUp?(question)
    }
}
