import Foundation
import Testing
@testable import whispermac

@Test
func parsesBasicSingleEntry() {
    let content = """
    1
    00:00:01,000 --> 00:00:04,500
    Hello world.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 1)
    #expect(segments[0].id == 0)
    #expect(segments[0].start == 1.0)
    #expect(segments[0].end == 4.5)
    #expect(segments[0].text == "Hello world.")
}

@Test
func parsesMultipleEntries() {
    let content = """
    1
    00:00:01,000 --> 00:00:02,000
    First.

    2
    00:00:03,250 --> 00:00:04,000
    Second.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 2)
    #expect(segments[0].id == 0)
    #expect(segments[0].text == "First.")
    #expect(segments[1].id == 1)
    #expect(segments[1].start == 3.25)
    #expect(segments[1].end == 4.0)
    #expect(segments[1].text == "Second.")
}

@Test
func joinsMultiLineTextWithNewline() {
    let content = """
    1
    00:00:01,000 --> 00:00:04,500
    First line.
    Second line.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 1)
    #expect(segments[0].text == "First line.\nSecond line.")
}

@Test
func toleratesMissingIndexLines() {
    let content = """
    00:00:01,000 --> 00:00:02,000
    First.

    00:00:03,000 --> 00:00:04,000
    Second.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 2)
    #expect(segments[0].text == "First.")
    #expect(segments[1].text == "Second.")
}

@Test
func parsesCRLFContent() {
    let content = "1\r\n00:00:01,000 --> 00:00:02,000\r\nHello.\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nWorld.\r\n"
    let segments = SRTParser.parse(content)
    #expect(segments.count == 2)
    #expect(segments[0].text == "Hello.")
    #expect(segments[1].text == "World.")
}

@Test
func parsesContentWithBOM() {
    let content = """
    \u{FEFF}1
    00:00:01,000 --> 00:00:02,000
    Hello.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 1)
    #expect(segments[0].text == "Hello.")
}

@Test
func skipsEntryWithMalformedTimestampMidFile() {
    let content = """
    1
    00:00:01,000 --> 00:00:02,000
    Good start.

    2
    not-a-timestamp --> 00:00:04,000
    Broken.

    3
    00:00:05,000 --> 00:00:06,000
    Good end.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 2)
    #expect(segments[0].text == "Good start.")
    #expect(segments[1].text == "Good end.")
}

@Test
func skipsBlankTextEntries() {
    let content = """
    1
    00:00:01,000 --> 00:00:02,000
    Real text.

    2
    00:00:03,000 --> 00:00:04,000

    3
    00:00:05,000 --> 00:00:06,000
    More text.
    """
    let segments = SRTParser.parse(content)
    #expect(segments.count == 2)
    #expect(segments[0].text == "Real text.")
    #expect(segments[1].text == "More text.")
}

@Test
func parsesEmptyContentToEmptyArray() {
    #expect(SRTParser.parse("").isEmpty)
    #expect(SRTParser.parse("   \n\n  ").isEmpty)
}

@Test
func formatsTimestampWithZeroPaddedHours() {
    // Display format is fixed-width "HH:MM:SS" with the fraction truncated.
    let content = """
    1
    01:01:01,500 --> 01:01:05,000
    Later.

    2
    00:01:23,400 --> 00:01:27,000
    Early.
    """
    let segments = SRTParser.parse(content)
    #expect(segments[0].start == 3661.5)
    #expect(segments[0].displayTimestamp == "01:01:01")
    #expect(segments[1].start == 83.4)
    #expect(segments[1].displayTimestamp == "00:01:23")
}

@Test
func loadRoundTripsTempSRTFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "whispermac-preview-\(UUID().uuidString).srt")
    defer { try? FileManager.default.removeItem(at: url) }

    let content = """
    1
    00:00:01,000 --> 00:00:02,500
    From disk.
    """
    try content.write(to: url, atomically: true, encoding: .utf8)

    let segments = try SRTParser.load(at: url)
    #expect(segments.count == 1)
    #expect(segments[0].text == "From disk.")
    #expect(segments[0].end == 2.5)
}

@Test
func loadThrowsForMissingFile() {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "whispermac-missing-\(UUID().uuidString).srt")
    #expect(throws: (any Error).self) {
        try SRTParser.load(at: url)
    }
}

@Test
func loadParsesFileWithBOMBytes() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "whispermac-bom-\(UUID().uuidString).srt")
    defer { try? FileManager.default.removeItem(at: url) }

    var data = Data([0xEF, 0xBB, 0xBF])
    data.append(Data("1\n00:00:01,000 --> 00:00:02,000\nBOM text.\n".utf8))
    try data.write(to: url)

    let segments = try SRTParser.load(at: url)
    #expect(segments.count == 1)
    #expect(segments[0].text == "BOM text.")
}

@Test
func loadToleratesInvalidUTF8Bytes() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "whispermac-badutf8-\(UUID().uuidString).srt")
    defer { try? FileManager.default.removeItem(at: url) }

    var data = Data("1\n00:00:01,000 --> 00:00:02,000\n".utf8)
    data.append(Data([0xFF, 0xFE]))
    data.append(Data("Damaged\n".utf8))
    try data.write(to: url)

    let segments = try SRTParser.load(at: url)
    #expect(segments.count == 1)
    #expect(segments[0].text.contains("Damaged"))
}
