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
func mediaDedupeKeyHonorsFilesystemCaseSensitivity() {
    let uppercase = URL(fileURLWithPath: "/tmp/media/Lecture.MP4")
    let lowercase = URL(fileURLWithPath: "/tmp/media/lecture.mp4")

    #expect(PanelHelper.mediaDedupeKey(for: uppercase, caseSensitive: false)
        == PanelHelper.mediaDedupeKey(for: lowercase, caseSensitive: false))
    #expect(PanelHelper.mediaDedupeKey(for: uppercase, caseSensitive: true)
        != PanelHelper.mediaDedupeKey(for: lowercase, caseSensitive: true))
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

@Test
func expandedMediaURLsRecursivelyFindsSupportedFilesAndSkipsHiddenAndPackageContents() async throws {
    let root = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fm = FileManager.default
    let sub1 = root.appending(path: "sub1", directoryHint: .isDirectory)
    let sub2 = sub1.appending(path: "sub2", directoryHint: .isDirectory)
    let hidden = root.appending(path: ".hidden", directoryHint: .isDirectory)
    let package = root.appending(path: "Sample.app", directoryHint: .isDirectory)
    for directory in [sub1, sub2, hidden, package] {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let mediaFiles = [
        root.appending(path: "a.mp4"),
        sub1.appending(path: "b.m4a"),
        sub2.appending(path: "c.flac"),
        root.appending(path: "d.MOV"),
        hidden.appending(path: "hidden.mp3"),
        package.appending(path: "bundled.mp4"),
    ]
    for file in mediaFiles { try Data("media".utf8).write(to: file) }
    try Data("text".utf8).write(to: root.appending(path: "notes.txt"))

    // A symlink cycle must not be followed by the recursive enumerator.
    try fm.createSymbolicLink(at: sub2.appending(path: "loop", directoryHint: .isDirectory), withDestinationURL: root)

    let expanded = await PanelHelper.expandedMediaURLs(from: [root, root])
    #expect(expanded.map(\.lastPathComponent) == ["a.mp4", "d.MOV", "b.m4a", "c.flac"])
}

@Test
func expandedMediaURLsPreservesTopLevelFileOrderAndDeduplicatesFolderAndFileInputs() async throws {
    let root = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folderA = root.appending(path: "folderA", directoryHint: .isDirectory)
    let folderB = root.appending(path: "folderB", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
    let nestedFile = folderA.appending(path: "file.mp4")
    let otherFile = folderB.appending(path: "clip.wav")
    let directFile = root.appending(path: "direct.mp3")
    for file in [nestedFile, otherFile, directFile] { try Data("media".utf8).write(to: file) }

    let expanded = await PanelHelper.expandedMediaURLs(from: [directFile, folderA, nestedFile, folderB])
    #expect(expanded.map(\.lastPathComponent) == ["direct.mp3", "file.mp4", "clip.wav"])

    let additions = PanelHelper.mediaFileAdditions(from: expanded, existing: [nestedFile])
    #expect(additions.map(\.lastPathComponent) == ["direct.mp3", "clip.wav"])
}

@Test
func expandedMediaURLsIgnoresEmptyAndNonexistentDirectories() async throws {
    let root = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let empty = root.appending(path: "empty", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    let missing = root.appending(path: "does-not-exist", directoryHint: .isDirectory)

    #expect(await PanelHelper.expandedMediaURLs(from: [empty, missing]).isEmpty)
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test
@MainActor
func appModelRejectsNewMediaDuringScanAndAllowsItAfterCompletion() async {
    let suiteName = "MediaScanState-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let gate = MediaURLExpanderGate()
    let model = AppModel(defaults: defaults, mediaURLExpander: { urls in await gate.expand(urls) })
    let first = URL(fileURLWithPath: "/tmp/first.mp4")
    let second = URL(fileURLWithPath: "/tmp/second.mov")

    model.addMediaURLs([first])
    #expect(model.isScanningMedia)
    model.addMediaURLs([second])
    await gate.waitForCallCount(1)
    let firstCallCount = await gate.callCount
    #expect(firstCallCount == 1)

    await gate.finishNext(with: [first])
    await model.waitForMediaScan()
    #expect(!model.isScanningMedia)
    #expect(model.inputFiles == [first])

    model.addMediaURLs([second])
    #expect(model.isScanningMedia)
    await gate.waitForCallCount(2)
    await gate.finishNext(with: [second])
    await model.waitForMediaScan()
    #expect(!model.isScanningMedia)
    #expect(model.inputFiles == [first, second])
}

@Test
@MainActor
func emptyExpansionReportsNoSupportedMedia() async {
    let (model, defaults, suiteName) = makeMediaAdditionModel(expanded: [])
    defer { defaults.removePersistentDomain(forName: suiteName) }

    model.addMediaURLs([URL(fileURLWithPath: "/tmp/drop-folder")])
    await model.waitForMediaScan()

    #expect(model.mediaAdditionFeedback == L.tr("media.no_supported_files"))
    #expect(model.inputFiles.isEmpty)
}

@Test
@MainActor
func expansionWithOnlyExistingFilesReportsNoNewMedia() async {
    let existing = URL(fileURLWithPath: "/tmp/already-queued.mp4")
    let (model, defaults, suiteName) = makeMediaAdditionModel(expanded: [existing])
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.inputFiles = [existing]

    model.addMediaURLs([URL(fileURLWithPath: "/tmp/drop-again")])
    await model.waitForMediaScan()

    #expect(model.mediaAdditionFeedback == L.tr("media.no_new_files"))
    #expect(model.inputFiles == [existing])
}

@Test
@MainActor
func expansionWithNewFileAddsItAndReportsCount() async {
    let newFile = URL(fileURLWithPath: "/tmp/new-file.mov")
    let (model, defaults, suiteName) = makeMediaAdditionModel(expanded: [newFile])
    defer { defaults.removePersistentDomain(forName: suiteName) }

    model.addMediaURLs([URL(fileURLWithPath: "/tmp/drop-folder")])
    await model.waitForMediaScan()

    #expect(model.mediaAdditionFeedback == L.tr("media.added_count", 1))
    #expect(model.inputFiles == [newFile])
}

@Test
@MainActor
func mixedExistingAndNewFilesOnlyAddsTheNewItem() async {
    let existing = URL(fileURLWithPath: "/tmp/already-queued.mp4")
    let newFile = URL(fileURLWithPath: "/tmp/new-file.m4a")
    let (model, defaults, suiteName) = makeMediaAdditionModel(expanded: [existing, newFile])
    defer { defaults.removePersistentDomain(forName: suiteName) }
    model.inputFiles = [existing]

    model.addMediaURLs([URL(fileURLWithPath: "/tmp/drop-mixed")])
    await model.waitForMediaScan()

    #expect(model.mediaAdditionFeedback == L.tr("media.added_count", 1))
    #expect(model.inputFiles == [existing, newFile])
}

@MainActor
private func makeMediaAdditionModel(expanded: [URL]) -> (AppModel, UserDefaults, String) {
    let suiteName = "MediaAdditionFeedback-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = AppModel(
        defaults: defaults,
        huggingFaceEnvironment: [:],
        mediaURLExpander: { _ in expanded }
    )
    return (model, defaults, suiteName)
}

private actor MediaURLExpanderGate {
    private var continuations: [CheckedContinuation<[URL], Never>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    func expand(_: [URL]) async -> [URL] {
        callCount += 1
        let ready = startWaiters.filter { $0.0 <= callCount }
        startWaiters.removeAll { $0.0 <= callCount }
        ready.forEach { $0.1.resume() }
        return await withCheckedContinuation { continuations.append($0) }
    }

    func waitForCallCount(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func finishNext(with urls: [URL]) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: urls)
    }
}
