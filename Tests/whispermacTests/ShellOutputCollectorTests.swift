import Foundation
import Testing
@testable import whispermac

@Suite
struct ShellOutputCollectorTests {
    @Test
    func decodesMixedLanguageUTF8WhenCharactersCrossReadBoundaries() {
        let collector = OutputCollector()
        let expected = "中文 English 日本語 한국어 café 🎙️"
        let data = Data((expected + "\n").utf8)
        let splitOffsets = [1, 2, 3, 6, 12, 17, 20, data.count - 1]
        var start = 0
        var lines: [String] = []

        for end in splitOffsets where end > start && end < data.count {
            lines += collector.appendLines(data[start..<end], to: .stdout)
            start = end
        }
        lines += collector.appendLines(data[start..<data.count], to: .stdout)

        #expect(lines == [expected])
        #expect(collector.snapshot().stdout == expected + "\n")
    }

    @Test
    func flushDecodesAnUnterminatedCompleteUTF8Line() {
        let collector = OutputCollector()
        let bytes = Data("末尾の字幕".utf8)
        let split = bytes.count - 1
        #expect(collector.appendLines(bytes[..<split], to: .stderr).isEmpty)
        #expect(collector.appendLines(bytes[split...], to: .stderr).isEmpty)
        #expect(collector.flushPendingLines().map(\.1) == ["末尾の字幕"])
    }

    @Test
    func oversizedLineIsDiscardedWithoutLosingFollowingLines() {
        let collector = OutputCollector()
        var bytes = Data(repeating: 0x61, count: OutputCollector.maximumBufferedLineBytes + 1)
        bytes.append(Data("\nnext line\n".utf8))
        #expect(collector.appendLines(bytes, to: .stdout) == ["next line"])
    }

    @Test
    func handlesCRLFAndBareCRAcrossChunks() {
        let collector = OutputCollector()
        #expect(collector.appendLines(Data("one\r".utf8), to: .stdout) == ["one"])
        #expect(collector.appendLines(Data("\ntwo\rthree\n".utf8), to: .stdout) == ["two", "three"])
    }
}
