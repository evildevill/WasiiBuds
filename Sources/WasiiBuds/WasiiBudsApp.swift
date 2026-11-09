import SwiftUI

@main
struct WasiiBudsApp: App {
    @StateObject private var explorer = BluetoothExplorer()

    var body: some Scene {
        WindowGroup {
            LaunchExperience(explorer: explorer)
                .preferredColorScheme(.light)
        }
    }
}
