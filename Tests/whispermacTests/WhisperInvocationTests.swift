import Foundation
import Testing
@testable import whispermac

@Test
func argumentsStartWithModelFlagAndPath() {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.txt]
    )

    #expect(arguments.count >= 2)
    #expect(arguments[0] == "-m")
    #expect(arguments[1] == "/models/ggml.bin")
}

@Test
func multipleInputsProduceOneFileFlagEachInInputOrder() {
    let wavPaths = ["/tmp/a.wav", "/tmp/b.wav", "/tmp/c.wav"]
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: wavPaths,
        outputPrefixes: ["/out/a", "/out/b", "/out/c"],
        formats: [.txt]
    )

    let fileFlags = arguments.indices.filter { arguments[$0] == "-f" }.map { arguments[$0 + 1] }
    #expect(fileFlags == wavPaths)
}

@Test
func oneOutputPrefixPerFileInInputOrder() {
    let outputPrefixes = ["/out/a", "/out/b"]
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav", "/tmp/b.wav"],
        outputPrefixes: outputPrefixes,
        formats: [.txt]
    )

    let prefixFlags = arguments.indices.filter { arguments[$0] == "-of" }.map { arguments[$0 + 1] }
    #expect(prefixFlags == outputPrefixes)
}

@Test
func progressAndLanguageFlagsArePresent() {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.txt]
    )

    #expect(arguments.contains("-pp"))
    let languageIndex = arguments.firstIndex(of: "-l")
    #expect(languageIndex != nil)
    #expect(arguments[languageIndex! + 1] == "auto")
}

@Test
func formatFlagsEmittedOnceEachSortedByRawValue() {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.srt, .txt]
    )

    #expect(arguments.filter { $0 == "-otxt" }.count == 1)
    #expect(arguments.filter { $0 == "-osrt" }.count == 1)
    let txtIndex = arguments.firstIndex(of: "-otxt") ?? -1
    let srtIndex = arguments.firstIndex(of: "-osrt") ?? -1
    #expect(srtIndex < txtIndex)
}

@Test
func modelPathIsTildeExpanded() {
    let arguments = WhisperInvocation.arguments(
        modelPath: "~/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.txt]
    )

    #expect(arguments[1] == NSString(string: "~/models/ggml.bin").expandingTildeInPath)
}

@Test
func languageFlagUsesSelectedSourceLanguage() throws {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.txt],
        sourceLanguage: "zh"
    )

    let languageIndex = try #require(arguments.firstIndex(of: "-l"))
    #expect(arguments[languageIndex + 1] == "zh")
}

@Test
func translateFlagIsEmittedWhenEnabled() {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.txt],
        translatesToEnglish: true
    )

    #expect(arguments.filter { $0 == "--translate" }.count == 1)
}

@Test
func translateFlagIsAbsentByDefault() {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.txt]
    )

    #expect(!arguments.contains("--translate"))
}

@Test
func vttAndJsonFormatFlagsAreEmittedOnceEachInSortedOrder() throws {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.json, .vtt]
    )

    #expect(arguments.filter { $0 == "-oj" }.count == 1)
    #expect(arguments.filter { $0 == "-ovtt" }.count == 1)
    #expect(!arguments.contains("-otxt"))
    #expect(!arguments.contains("-osrt"))
    let jsonIndex = try #require(arguments.firstIndex(of: "-oj"))
    let vttIndex = try #require(arguments.firstIndex(of: "-ovtt"))
    #expect(jsonIndex < vttIndex)
}

@Test
func srtAndJsonFormatFlagsAreOrderedByRawValue() throws {
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav"],
        outputPrefixes: ["/out/a"],
        formats: [.srt, .json]
    )

    let jsonIndex = try #require(arguments.firstIndex(of: "-oj"))
    let srtIndex = try #require(arguments.firstIndex(of: "-osrt"))
    #expect(jsonIndex < srtIndex)
}

@Test
func exactArgumentOrderForTwoFileBatch() {
    // Canonical order: model, -f/-of pairs, -l <language>, -pp, [--translate], format flags sorted by rawValue.
    // --translate is a mode modifier grouped with the language block; format flags keep their
    // deterministic rawValue sort (json < srt < txt < vtt).
    let arguments = WhisperInvocation.arguments(
        modelPath: "/models/ggml.bin",
        wavPaths: ["/tmp/a.wav", "/tmp/b.wav"],
        outputPrefixes: ["/out/a", "/out/b"],
        formats: [.txt, .srt],
        sourceLanguage: "zh",
        translatesToEnglish: true
    )

    #expect(arguments == [
        "-m", "/models/ggml.bin",
        "-f", "/tmp/a.wav",
        "-f", "/tmp/b.wav",
        "-of", "/out/a",
        "-of", "/out/b",
        "-l", "zh",
        "-pp",
        "--translate",
        "-osrt",
        "-otxt",
    ])
}

@Test
func legacyPersistedFormatRawValuesDecodeUnchanged() {
    let decoded = Set(["srt", "txt"].compactMap(OutputFormat.init(rawValue:)))

    #expect(decoded == [.txt, .srt])
    #expect(Set(OutputFormat.allCases.map(\.rawValue)) == ["txt", "srt", "vtt", "json"])
    #expect(OutputFormat.vtt.whisperArgument == "-ovtt")
    #expect(OutputFormat.json.whisperArgument == "-oj")
}
