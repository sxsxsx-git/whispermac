import Foundation

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: Int
    let start: Double
    let end: Double
    let text: String

    /// Fixed-width "HH:MM:SS" display form of `start`, fraction truncated.
    var displayTimestamp: String {
        let total = Int(start)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

struct TranscriptPreviewFile: Identifiable, Equatable, Sendable {
    let id: URL
    let url: URL
    let displayName: String
}

enum TranscriptPreview {
    /// Upper bound for the published live segment list so streaming runs cannot
    /// grow the SwiftUI list without limit.
    static let liveSegmentLimit = 300

    /// Appends `segment` to `segments` while keeping at most the last `limit`
    /// entries in order. The caller-provided id is replaced with a monotonically
    /// increasing one so ids stay unique and stable for ForEach even after
    /// eviction from the front.
    static func appendCapped(
        _ segment: TranscriptSegment,
        to segments: [TranscriptSegment],
        limit: Int
    ) -> [TranscriptSegment] {
        guard limit > 0 else { return [] }
        let nextID = (segments.last?.id ?? -1) + 1
        var result = segments
        result.append(TranscriptSegment(id: nextID, start: segment.start, end: segment.end, text: segment.text))
        if result.count > limit {
            result.removeFirst(result.count - limit)
        }
        return result
    }
}

/// Parses whisper-cli stdout segment lines, e.g.
/// `[00:00:00.000 --> 00:00:00.340]   Hello.`
/// The bundled build prints `[HH:MM:SS.mmm --> HH:MM:SS.mmm]` followed by two
/// format spaces plus the raw whisper text, which itself usually begins with a
/// space; an MM:SS.mmm variant is tolerated. Anything else yields nil.
enum LiveSegmentParser {
    static func parse(_ line: String) -> TranscriptSegment? {
        guard line.hasPrefix("["), let closing = line.firstIndex(of: "]") else {
            return nil
        }
        let bracketed = line[line.index(after: line.startIndex)..<closing]
        let parts = bracketed.split(separator: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(String(parts[0])),
              let end = parseTimestamp(String(parts[1]))
        else { return nil }
        let text = String(line[line.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return TranscriptSegment(id: 0, start: start, end: end, text: text)
    }

    /// Accepts "HH:MM:SS.mmm" (observed) and "MM:SS.mmm"; rejects anything else.
    private static func parseTimestamp(_ text: String) -> Double? {
        let clockAndFraction = text.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard clockAndFraction.count == 2 else { return nil }
        let clock = clockAndFraction[0].split(separator: ":")
        guard (2...3).contains(clock.count) else { return nil }
        let leadingComponents = clock.dropLast().map { Double($0) ?? -1 }
        guard leadingComponents.allSatisfy({ $0 >= 0 }),
              let seconds = Double("\(clock.last!).\(clockAndFraction[1])")
        else { return nil }
        let minutes = leadingComponents.last ?? 0
        let hours = leadingComponents.dropLast().last ?? 0
        return hours * 3600 + minutes * 60 + seconds
    }
}

enum SRTParser {
    /// Parses SRT subtitle content into transcript segments.
    ///
    /// Tolerant by design: index lines are optional, CRLF and a leading UTF-8 BOM are
    /// normalized, and blocks with malformed timestamps or blank text are skipped.
    /// Multi-line text is joined with "\n".
    static func parse(_ content: String) -> [TranscriptSegment] {
        var normalized = content
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        normalized = normalized
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var segments: [TranscriptSegment] = []
        for var lines in blocks(in: normalized) {
            if let first = lines.first, lines.count > 1, Int(first) != nil {
                lines.removeFirst()
            }
            guard let timestampLine = lines.first, let range = parseTimestamps(timestampLine) else {
                continue
            }
            let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            segments.append(TranscriptSegment(id: segments.count, start: range.start, end: range.end, text: text))
        }
        return segments
    }

    /// Reads an .srt file from disk, decoding UTF-8 lossily; throws on I/O failure.
    static func load(at url: URL) throws -> [TranscriptSegment] {
        let data = try Data(contentsOf: url)
        return parse(String(decoding: data, as: UTF8.self))
    }

    private static func blocks(in normalized: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
            } else {
                current.append(String(line))
            }
        }
        if !current.isEmpty {
            blocks.append(current)
        }
        return blocks
    }

    private static func parseTimestamps(_ line: String) -> (start: Double, end: Double)? {
        let parts = line.split(separator: "-->")
        guard parts.count == 2,
              let start = parseTimestamp(String(parts[0])),
              let end = parseTimestamp(String(parts[1]))
        else { return nil }
        return (start, end)
    }

    private static func parseTimestamp(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let components = trimmed.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard components.count == 3 else { return nil }
        guard let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
