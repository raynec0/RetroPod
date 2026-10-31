import SwiftUI

@main
struct RetroPodApp: App {
    @StateObject private var lib = Library.shared
    @StateObject private var player = Player.shared
    @StateObject private var nav = Navigator()
    @Environment(\.scenePhase) private var phase

    init() {
        Player.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            IPodView()
                .environmentObject(lib)
                .environmentObject(player)
                .environmentObject(nav)
                .onOpenURL { url in lib.importFiles([url]) }
                .onChange(of: phase) { p in
                    if p == .active { Task { await lib.scan() } }
                }
        }
    }
}
