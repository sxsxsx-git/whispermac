import SwiftUI

@main
struct WhisperMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("WhisperMac") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowResizability(.contentSize)
    }
}
