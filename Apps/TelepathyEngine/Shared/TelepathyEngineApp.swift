import SwiftUI

@main
struct TelepathyEngineApp: App {
    @StateObject private var model = EngineViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear { model.bootstrap() }
        }
#if os(macOS)
        .defaultSize(width: 1280, height: 820)
#endif
    }
}
