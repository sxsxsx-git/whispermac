import AppKit
import UniformTypeIdentifiers

enum PanelHelper {
    static let supportedMediaTypes: [UTType] = [
        .mpeg4Movie,
        UTType(filenameExtension: "m4a"),
        UTType(filenameExtension: "mp3"),
        UTType(filenameExtension: "wav"),
        UTType(filenameExtension: "aac"),
    ].compactMap { $0 }

    static func supportsFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return supportedMediaTypes.contains(where: { type.conforms(to: $0) || $0.conforms(to: type) })
    }

    @MainActor
    static func chooseBinary() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
