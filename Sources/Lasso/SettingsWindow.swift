import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var onShortcutChange: ((Shortcut) -> Void)?

    func show() {
        let hosting = NSHostingController(
            rootView: SettingsView(
                onSaved: { [weak self] in self?.window?.close() },
                onShortcutChange: { [weak self] shortcut in self?.onShortcutChange?(shortcut) }
            )
        )
        let w: NSWindow
        if let existing = window {
            w = existing
            w.contentViewController = hosting
        } else {
            w = NSWindow(contentViewController: hosting)
            w.title = "Lasso Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @State private var apiKey = KeyStore.read() ?? ""
    @State private var errorMessage: String?
    @State private var shortcut = Shortcut.load()
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    var onSaved: () -> Void
    var onShortcutChange: (Shortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Press \(shortcut.displayString) to lasso anything on screen.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini API Key")
                    .font(.headline)
                SecureField("AIza…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Link("Get a free key at aistudio.google.com",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcut")
                    .font(.headline)
                HStack {
                    Button(isRecording ? "Press keys… (⎋ to cancel)" : shortcut.displayString) {
                        isRecording ? stopRecording() : startRecording()
                    }
                    if shortcut != .default && !isRecording {
                        Button("Reset") {
                            apply(.default)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                Text("Hold ⌃, ⌥ or ⌘ plus a key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text(UsageStore.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    do {
                        try KeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        onSaved()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels
                stopRecording()
                return nil
            }
            guard let recorded = Shortcut.from(event: event) else { return nil }
            apply(recorded)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        isRecording = false
    }

    private func apply(_ new: Shortcut) {
        new.save()
        shortcut = new
        onShortcutChange(new)
    }
}
