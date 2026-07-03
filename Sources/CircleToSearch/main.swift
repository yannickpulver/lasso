import AppKit

// main.swift's top-level code runs on the main thread but is not
// automatically MainActor-isolated by the compiler; AppDelegate and its
// dependencies (ShapeOverlay, ResultPanel) are @MainActor, so we assert
// isolation explicitly here (safe: this is the process's main thread).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
