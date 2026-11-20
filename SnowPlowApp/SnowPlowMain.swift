import SwiftUI
import SwiftData

@main
struct SnowPlowMain: App {
    @State private var locationService = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
        }
        .modelContainer(for: [Customer.self, Property.self, Storm.self, ServiceRecord.self])
    }
}
