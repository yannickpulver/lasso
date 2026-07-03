import Foundation

/// Structured answer shared by all providers.
public struct Answer {
    public struct Source {
        public let title: String
        public let url: URL

        public init(title: String, url: URL) {
            self.title = title
            self.url = url
        }
    }

    public let title: String
    public let body: String
    public let address: String?
    public let sources: [Source]

    /// Parses provider text: first non-empty line = title, an optional
    /// "ADDRESS: ..." line is extracted, the rest is the body.
    public static func parse(text: String, sources: [Source] = []) -> Answer {
        var address: String?
        var lines: [String] = []

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("ADDRESS:") {
                let value = trimmed.dropFirst("ADDRESS:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { address = value }
            } else {
                lines.append(line)
            }
        }

        guard let firstIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            return Answer(
                title: text.trimmingCharacters(in: .whitespacesAndNewlines),
                body: "",
                address: address,
                sources: sources
            )
        }

        let title = lines[firstIndex].trimmingCharacters(in: .whitespaces)
        let body = lines[(firstIndex + 1)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Answer(title: title, body: body, address: address, sources: sources)
    }
}
