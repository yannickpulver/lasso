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

    public enum Kind: String {
        case product // physical good
        case digital // software, apps, websites, media
        case place
        case other
    }

    public let title: String
    public let body: String
    public let address: String?
    public let sources: [Source]
    public let kind: Kind
    public let followUps: [String]
    /// Direct action links the model surfaced ("Watch on YouTube" → URL).
    public let links: [Source]

    public init(
        title: String,
        body: String,
        address: String?,
        sources: [Source],
        kind: Kind = .other,
        followUps: [String] = [],
        links: [Source] = []
    ) {
        self.title = title
        self.body = body
        self.address = address
        self.sources = sources
        self.kind = kind
        self.followUps = followUps
        self.links = links
    }

    /// The bare entity name from the title ("NAME — what it is" → "NAME"),
    /// used to build search/maps queries.
    public var entityName: String {
        let separators = [" — ", " – ", " - "]
        for separator in separators {
            if let range = title.range(of: separator) {
                return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return title
    }

    /// Parses provider text: first non-empty line = title; machine lines
    /// "ADDRESS: …", "KIND: …" and "FOLLOWUP: …" are extracted; the rest is
    /// the body.
    public static func parse(text: String, sources: [Source] = []) -> Answer {
        var address: String?
        var kind: Kind = .other
        var followUps: [String] = []
        var links: [Source] = []
        var lines: [String] = []

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("ADDRESS:") {
                let value = trimmed.dropFirst("ADDRESS:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { address = value }
            } else if upper.hasPrefix("KIND:") {
                let value = trimmed.dropFirst("KIND:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                kind = Kind(rawValue: value) ?? .other
            } else if upper.hasPrefix("LINK:") {
                let value = trimmed.dropFirst("LINK:".count)
                let parts = value.split(separator: "|", maxSplits: 1)
                if parts.count == 2,
                   let url = URL(string: parts[1].trimmingCharacters(in: .whitespaces)),
                   url.scheme?.hasPrefix("http") == true {
                    links.append(Source(
                        title: parts[0].trimmingCharacters(in: .whitespaces),
                        url: url
                    ))
                }
            } else if upper.hasPrefix("FOLLOWUP:") {
                let value = trimmed.dropFirst("FOLLOWUP:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { followUps.append(value) }
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
                sources: sources,
                kind: kind,
                followUps: followUps,
                links: links
            )
        }

        let title = lines[firstIndex].trimmingCharacters(in: .whitespaces)
        let body = lines[(firstIndex + 1)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Answer(
            title: title,
            body: body,
            address: address,
            sources: sources,
            kind: kind,
            followUps: followUps,
            links: links
        )
    }
}
