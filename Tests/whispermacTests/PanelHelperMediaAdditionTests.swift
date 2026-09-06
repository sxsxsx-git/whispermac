import Foundation
import Testing
import UniformTypeIdentifiers
@testable import whispermac

@Test
func mediaFileAdditionsAcceptsSupportedMediaAndRejectsUnsupported() {
    let candidates = [
        URL(fileURLWithPath: "/tmp/media/movie.mp4"),
        URL(fileURLWithPath: "/tmp/media/notes.txt"),
        URL(fileURLWithPath: "/tmp/media/clip.mov"),
        URL(fileURLWithPath: "/tmp/media/video.m4v"),
        URL(fileURLWithPath: "/tmp/media/song.flac"),
        URL(fileURLWithPath: "/tmp/media/talk.mp3"),
        URL(fileURLWithPath: "/tmp/media/paper.pdf"),
        URL(fileURLWithPath: "/tmp/media/recording.ogg"),
    ]

    let additions = PanelHelper.mediaFileAdditions(from: candidates, existing: [])

    #expect(additions.map { $0.lastPathComponent } == ["movie.mp4", "clip.mov", "video.m4v", "song.flac", "talk.mp3"])
}

@Test
func mediaFileAdditionsDeduplicatesWithinCandidates() {
    let candidates = [
        URL(fileURLWithPath: "/tmp/media/a.mp4"),
        URL(fileURLWithPath: "/tmp/media/b.mov"),
        URL(fileURLWithPath: "/tmp/media/a.mp4"),
    ]

    let additions = PanelHelper.mediaFileAdditions(from: candidates, existing: [])

    #expect(additions.map { $0.lastPathComponent } == ["a.mp4", "b.mov"])
}

@Test
func mediaFileAdditionsDeduplicatesAgainstExistingCaseInsensitively() {
    let existing = [URL(fileURLWithPath: "/tmp/media/Interview.MP4")]
    let candidates = [
        URL(fileURLWithPath: "/tmp/media/interview.mp4"),
        URL(fileURLWithPath: "/tmp/media/other.mov"),
    ]

    let additions = PanelHelper.mediaFileAdditions(from: candidates, existing: existing)

    #expect(additions.map { $0.lastPathComponent } == ["other.mov"])
}

@Test
func mediaFileAdditionsComparesStandardizedPaths() {
    let existing = [URL(fileURLWithPath: "/tmp/media/a.mp4")]
    let candidates = [
        URL(fileURLWithPath: "/tmp/media/./a.mp4"),
        URL(fileURLWithPath: "/tmp/media/../media/a.mp4"),
        URL(fileURLWithPath: "/tmp/media/b.flac"),
    ]

    let additions = PanelHelper.mediaFileAdditions(from: candidates, existing: existing)

    #expect(additions.map { $0.lastPathComponent } == ["b.flac"])
}

@Test
func mediaFileAdditionsPreservesCandidateOrder() {
    let candidates = [
        URL(fileURLWithPath: "/tmp/media/z.flac"),
        URL(fileURLWithPath: "/tmp/media/notes.txt"),
        URL(fileURLWithPath: "/tmp/media/a.mp4"),
        URL(fileURLWithPath: "/tmp/media/c.mov"),
    ]

    let additions = PanelHelper.mediaFileAdditions(from: candidates, existing: [])

    #expect(additions.map { $0.lastPathComponent } == ["z.flac", "a.mp4", "c.mov"])
}

@Test
func mediaFileAdditionsHandlesEmptyInputs() {
    #expect(PanelHelper.mediaFileAdditions(from: [], existing: []).isEmpty)
    #expect(PanelHelper.mediaFileAdditions(from: [], existing: [URL(fileURLWithPath: "/tmp/media/a.mp4")]).isEmpty)
}

@Test
func mediaFileAdditionsAcceptsUppercaseExtensions() {
    let candidates = [
        URL(fileURLWithPath: "/tmp/media/INTERVIEW.MOV"),
        URL(fileURLWithPath: "/tmp/media/SONG.MP3"),
        URL(fileURLWithPath: "/tmp/media/CLIP.M4V"),
    ]

    let additions = PanelHelper.mediaFileAdditions(from: candidates, existing: [])

    #expect(additions.count == 3)
}

@Test
func supportedMediaTypesIncludeQuickTimeM4VAndFLAC() throws {
    let mov = try #require(UTType(filenameExtension: "mov"))
    let m4v = try #require(UTType(filenameExtension: "m4v"))
    let flac = try #require(UTType(filenameExtension: "flac"))

    #expect(PanelHelper.supportedMediaTypes.contains(mov))
    #expect(PanelHelper.supportedMediaTypes.contains(m4v))
    #expect(PanelHelper.supportedMediaTypes.contains(flac))
}
