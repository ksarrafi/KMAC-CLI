import SwiftUI

@main
struct KMacPilotApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.isConnected {
                MainTabView()
                    .environmentObject(appState)
            } else {
                ConnectView()
                    .environmentObject(appState)
            }
        }
    }
}
