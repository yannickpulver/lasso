import AppKit
import CoreGraphics
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
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    var onSaved: () -> Void
    var onShortcutChange: (Shortcut) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lasso.badge.sparkles")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lasso anything on screen")
                        .font(.headline)
                    HStack(spacing: 5) {
                        Text("Press")
                        Text(shortcut.displayString)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(.quaternary.opacity(0.6))
                            )
                        Text("and draw around it.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.12), Color.pink.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )

            GroupBox("Gemini API Key") {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("AIza…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get a free key at aistudio.google.com",
                         destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Shortcut") {
                VStack(alignment: .leading, spacing: 6) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Permissions") {
                HStack(spacing: 8) {
                    Image(systemName: screenRecordingGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(screenRecordingGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Recording")
                        if !screenRecordingGranted {
                            Text("Required to capture what you lasso. Relaunch Lasso after granting.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !screenRecordingGranted {
                        Button("Grant…") { requestScreenRecording() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
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
        .frame(width: 400)
        .onDisappear { stopRecording() }
        // Re-check when the window regains focus (e.g. returning from System Settings).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private func requestScreenRecording() {
        // Prompts on first ask; if previously denied, macOS shows nothing —
        // send the user to the settings pane as well.
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )!)
        }
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
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
