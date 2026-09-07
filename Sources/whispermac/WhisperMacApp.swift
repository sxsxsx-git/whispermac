import SwiftUI
import Combine

@main
struct WhisperMacApp: App {
    @StateObject private var model: AppModel

    init() {
        let createdModel = AppModel()
        _model = StateObject(wrappedValue: createdModel)
        #if DEBUG
        DebugDriverMonitor.installShared(model: createdModel)
        #endif
    }

    var body: some Scene {
        WindowGroup("WhisperMac") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}

#if DEBUG
/// Manual UI-verification helper, compiled only in DEBUG and inert unless the
/// app is launched with `WHISPERMAC_SNAPSHOT_DIR=<dir>`. Automated checks drop
/// files into that directory:
///   `<name>.path`  — writes `<name>.png` capturing the key window's live
///                    content in-process (own-window CGWindowList capture, so
///                    it needs no screen-recording permission).
///   `<name>.cmd`   — one command per line, driving the same public AppModel
///                    methods the buttons call: `add:<path>|<path>`, `start`,
///                    `cancel`, `clear`, `dismiss`, `lang:en|zh-Hans|ja`,
///                    `appearance:light|dark`, `resize-content:<w>x<h>` (sets
///                    the key window's content size, anchoring the top-left
///                    corner, clamped by the window's min size).
/// It exists so interface states can be exercised and captured end to end;
/// it is not part of the product and never ships in release builds.
@MainActor
final class DebugDriverMonitor {
    private static var shared: DebugDriverMonitor?

    static func installShared(model: AppModel) {
        guard shared == nil, let monitor = DebugDriverMonitor(model: model) else { return }
        shared = monitor
        monitor.start()
    }

    private let model: AppModel
    private let directory: String
    private var timer: Timer?
    private var handledSignals = Set<String>()

    private init?(model: AppModel) {
        guard let directory = ProcessInfo.processInfo.environment["WHISPERMAC_SNAPSHOT_DIR"],
              !directory.isEmpty
        else { return nil }
        self.model = model
        self.directory = directory
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    private func poll() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
        for entry in entries where entry.hasSuffix(".path") || entry.hasSuffix(".cmd") {
            guard !handledSignals.contains(entry) else { continue }
            handledSignals.insert(entry)

            let signalPath = (directory as NSString).appendingPathComponent(entry)
            let extensionLength = entry.hasSuffix(".path") ? 5 : 4
            let name = String(entry.dropLast(extensionLength))
            let signalURL = URL(fileURLWithPath: signalPath)

            if entry.hasSuffix(".cmd") {
                let lines = (try? String(contentsOf: signalURL, encoding: .utf8))?
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty } ?? []
                for line in lines {
                    run(command: line)
                }
            } else {
                snapshotWindow(to: URL(fileURLWithPath: (directory as NSString).appendingPathComponent(name + ".png")))
            }
            try? fileManager.removeItem(at: signalURL)
        }
    }

    private func run(command: String) {
        guard let separator = command.firstIndex(of: ":") else {
            runBare(command: command)
            return
        }
        let name = String(command[..<separator])
        let payload = String(command[command.index(after: separator)...])
        switch name {
        case "add":
            let urls = payload.split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            model.addMediaURLs(urls)
        case "lang":
            let language = AppLanguage(rawValue: payload) ?? AppLanguage(identifier: payload)
            model.appLanguage = language
        case "appearance":
            NSApp.appearance = NSAppearance(named: payload == "light" ? .aqua : .darkAqua)
        case "resize", "resize-content":
            // The SwiftUI content view is the root layout here (the toolbar
            // lives in the title bar), so a content-rect resize targets the
            // root layout size; verify the rendered result regardless.
            let parts = payload.split(separator: "x", maxSplits: 1)
            if parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) {
                resizeWindow(width: width, height: height)
            }
        default:
            break
        }
    }

    private func runBare(command: String) {
        switch command {
        case "start":
            model.startTranscription()
        case "cancel":
            model.cancelTranscription()
        case "clear":
            model.clearInputFiles()
        case "dismiss":
            model.dismissOutcome()
        default:
            break
        }
    }

    private func resizeWindow(width: Double, height: Double) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else {
            FileHandle.standardError.write(Data("[resize] no window found\n".utf8))
            return
        }
        FileHandle.standardError.write(Data("[resize] before frame=\(window.frame)\n".utf8))
        let contentFrame = window.contentRect(forFrameRect: window.frame)
        var targetContentFrame = contentFrame
        targetContentFrame.size = NSSize(width: width, height: height)
        targetContentFrame.origin = NSPoint(
            x: contentFrame.minX,
            y: contentFrame.maxY - height
        )
        window.setFrame(window.frameRect(forContentRect: targetContentFrame), display: true)
        FileHandle.standardError.write(Data("[resize] after frame=\(window.frame)\n".utf8))
    }

    private func snapshotWindow(to outputURL: URL) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else {
            FileHandle.standardError.write(Data("[snapshot] no key/visible window; windows=\(NSApp.windows.count)\n".utf8))
            return
        }
        // Capture the live window in-process: CGWindowListCreateImage on the
        // app's own window needs no screen-recording permission, and unlike
        // ImageRenderer it draws real AppKit-backed controls (List, Menu,
        // borderless buttons), which SwiftUI cannot re-render offscreen.
        let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution]
        )
        guard let image else {
            FileHandle.standardError.write(Data("[snapshot] capture failed for window \(window.windowNumber)\n".utf8))
            return
        }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: outputURL)
    }
}
#endif
