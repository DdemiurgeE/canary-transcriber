import Foundation

/// Applies a speaker rename to an existing `.canary.md` file **without regenerating it**, so
/// transcript text, user notes, front matter and hand edits survive. Only the generated speaker
/// labels are rewritten: the alias cell of the `## Speakers` table and the `**alias (SPEAKER_XX)**`
/// labels in the `## Transcript` section.
///
/// The previous alias is not needed: any transcript label that is the raw speaker id or ends with
/// `(SPEAKER_XX)` is recognised, so renaming twice or clearing an alias both work.
/// Escaping mirrors `MeetingWorkspace.markdownInline`, keeping a patched file identical to a fresh
/// render that had the same alias from the start.
public enum SessionMarkdownEditing {
    public static func renamingSpeaker(in markdown: String, speaker: String, alias: String) -> String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let newLabel = trimmed.isEmpty ? escape(speaker) : "\(escape(trimmed)) (\(escape(speaker)))"
        let suffix = "(\(speaker))"

        var section = ""
        var fenced = false
        return markdown.components(separatedBy: "\n").map { line in
            if line.hasPrefix("```") || line.hasPrefix("~~~") { fenced.toggle() }
            guard !fenced else { return line }
            if line.hasPrefix("## ") { section = line; return line }
            if section == "## Speakers", let rewritten = rewritingSpeakersRow(line, speaker: speaker, alias: trimmed) {
                return rewritten
            }
            if section == "## Transcript", let label = transcriptLabel(of: line) {
                let decoded = unescape(label)
                if decoded == speaker || decoded.hasSuffix(suffix) {
                    return "**\(newLabel)**" + line.dropFirst(label.count + 4)
                }
            }
            return line
        }.joined(separator: "\n")
    }

    /// The `SPEAKER_XX` / `Alice (SPEAKER_XX)` label of a generated transcript line, or `nil` when
    /// the line is not one of ours (`**label** [start - end]: text`).
    private static func transcriptLabel(of line: String) -> String? {
        guard line.hasPrefix("**") else { return nil }
        let afterOpening = line.dropFirst(2)
        guard let closing = afterOpening.range(of: "**") else { return nil }
        let label = String(afterOpening[..<closing.lowerBound])
        guard !label.isEmpty else { return nil }
        let remainder = afterOpening[closing.upperBound...]
        guard remainder.hasPrefix(" [") else { return nil }
        return label
    }

    /// Rewrites only the `Alias` cell of a generated `| Speaker | Segments | Duration | Alias |`
    /// row, preserving the surrounding cell padding. Returns `nil` for anything that is not one of
    /// our generated rows, so hand-edited tables are left alone.
    private static func rewritingSpeakersRow(_ line: String, speaker: String, alias: String) -> String? {
        guard line.hasPrefix("|"), line.hasSuffix("|"), !line.contains("\\|") else { return nil }
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard cells.count >= 6 else { return nil }
        guard unescape(cells[1].trimmingCharacters(in: .whitespaces)) == speaker else { return nil }
        let segments = cells[2].trimmingCharacters(in: .whitespaces)
        guard !segments.isEmpty, segments.allSatisfy(\.isNumber) else { return nil }
        cells[4] = alias.isEmpty ? "  " : " \(escape(alias)) "
        return cells.joined(separator: "|")
    }

    /// Inverse of `escape`, used only for comparison against raw speaker ids and aliases.
    private static func unescape(_ value: String) -> String {
        var result = value
        for character in ["`", "*", "_", "[", "]", "|"] {
            result = result.replacingOccurrences(of: "\\" + character, with: character)
        }
        return result.replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Same escaping as `MeetingWorkspace.markdownInline` plus newline flattening for table cells.
    private static func escape(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\\", with: "\\\\")
        for character in ["`", "*", "_", "[", "]", "|"] {
            result = result.replacingOccurrences(of: character, with: "\\" + character)
        }
        return result.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
