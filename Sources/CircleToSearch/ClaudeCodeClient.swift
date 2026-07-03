import Foundation

/// Answers via the local `claude` CLI (Claude Code headless mode) — uses the
/// user's Claude subscription, no API key required.
enum ClaudeCodeClient {
    private static let claudePath: String? = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }()

    static var isAvailable: Bool { claudePath != nil }

    static func ask(imageData: Data) async throws -> String {
        guard let claudePath else {
            throw ClaudeError.apiError("claude CLI not found. Install Claude Code or set ANTHROPIC_API_KEY.")
        }

        // Run claude with cwd set to a temp dir containing the screenshot so
        // the Read tool can access it without permission prompts.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("circle-to-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        try imageData.write(to: workDir.appendingPathComponent("capture.png"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = workDir
        process.arguments = [
            "-p",
            "Look at the image file capture.png in the current directory. " + AnswerPrompt.text
                + " You may use your web search capability to identify what you see.",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClaudeError.apiError(message?.isEmpty == false ? message! : "claude CLI failed")
        }

        let text = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw ClaudeError.badResponse }
        return text
    }
}
