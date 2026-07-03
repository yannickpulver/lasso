import Foundation

enum ScreenCapture {
    /// Captures the given screen rect (top-left-origin global coordinates)
    /// via the native screencapture CLI. Returns PNG data or nil.
    static func capture(rect: CGRect) -> Data? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("circle-to-search-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -x: no sound, -R: capture rect
        process.arguments = ["-x", "-R", region, fileURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return nil
        }
        return data
    }
}
