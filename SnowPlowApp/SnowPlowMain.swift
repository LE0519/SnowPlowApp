import SwiftUI
import SwiftData

@main
struct SnowPlowMain: App {
    @State private var locationService = LocationService()
    @State private var syncService = SyncService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
                .environment(syncService)
        }
        .modelContainer(for: [Customer.self, Property.self, Storm.self, ServiceRecord.self])
    }
}
