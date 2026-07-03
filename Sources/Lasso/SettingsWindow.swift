import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(onSaved: { [weak self] in self?.window?.close() })
            )
            let w = NSWindow(contentViewController: hosting)
            w.title = "Lasso Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @State private var apiKey = KeyStore.read() ?? ""
    @State private var errorMessage: String?
    var onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gemini API Key")
                .font(.headline)
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
            HStack {
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
        .frame(width: 360)
    }
}
