import Foundation

public struct SpeakerSegment: Equatable, Codable {
    public let speaker: String
    public let start: Double
    public let end: Double
    public let text: String

    public init(speaker: String, start: Double, end: Double, text: String) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct MeetingWorkspace {
    public let sourceName: String
    public let segments: [SpeakerSegment]
    public let aliases: [String: String]
    public let fallbackText: String

    public init(sourceName: String, segments: [SpeakerSegment], aliases: [String: String], fallbackText: String) {
        self.sourceName = sourceName
        self.segments = segments
        self.aliases = aliases
        self.fallbackText = fallbackText
    }

    public func render() -> String {
        let usableSegments = segments.filter { !$0.speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usableSegments.isEmpty else {
            return "# Transcript: \(markdownHeading(sourceName))\n\n\(markdownText(fallbackText))\n"
        }

        var lines = ["# Transcript: \(markdownHeading(sourceName))", "", "## Speakers", "", "| Speaker | Segments | Duration | Alias |", "|---|---:|---:|---|"]
        for speaker in speakerNames(in: usableSegments) {
            let speakerSegments = usableSegments.filter { $0.speaker == speaker }
            let duration = speakerSegments.reduce(0) { $0 + max(0, $1.end - $1.start) }
            let alias = aliases[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lines.append("| \(markdownTableCell(speaker)) | \(speakerSegments.count) | \(formatDuration(duration)) | \(markdownTableCell(alias)) |")
        }

        lines += ["", "## Transcript", ""]
        let transcriptLines = usableSegments.compactMap { segment -> String? in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "**\(markdownInline(displayName(for: segment.speaker)))** [\(formatTime(segment.start)) - \(formatTime(segment.end))]: \(markdownText(text))"
        }
        if transcriptLines.isEmpty {
            lines.append(markdownText(fallbackText))
        } else {
            lines.append(contentsOf: transcriptLines)
        }

        lines += ["", "## Summary", "", "## Decisions", "", "## Action items", "", "## Open questions", ""]
        return lines.joined(separator: "\n")
    }

    private func speakerNames(in segments: [SpeakerSegment]) -> [String] {
        Array(Set(segments.map(\.speaker))).sorted()
    }

    private func displayName(for speaker: String) -> String {
        guard let alias = aliases[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty else {
            return speaker
        }
        return "\(alias) (\(speaker))"
    }

    private func markdownHeading(_ value: String) -> String {
        markdownInline(value).replacingOccurrences(of: "\n", with: " ")
    }

    private func markdownInline(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private func markdownText(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { markdownInline(String($0)) }
            .joined(separator: "  \n")
    }

    private func markdownTableCell(_ value: String) -> String {
        markdownInline(value).replacingOccurrences(of: "\n", with: " ")
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func formatDuration(_ seconds: Double) -> String {
        formatTime(seconds)
    }
}
