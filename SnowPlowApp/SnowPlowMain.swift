import SwiftUI
import SwiftData

@main
struct SnowPlowMain: App {
    private let container: ModelContainer
    @State private var locationService: LocationService
    @State private var syncService: SyncService

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Customer.self, Property.self, Storm.self, ServiceRecord.self
            )
        } catch {
            fatalError("Could not open the SnowPlow database: \(error)")
        }
        self.container = container

        // These are set up here, not on a screen, so they also work when iOS restarts
        // the app in the background during a storm.
        let context = container.mainContext
        DataMaintenance.assignMissingIDs(in: context)

        let location = LocationService()
        location.configure(context: context)

        let sync = SyncService()
        sync.configure(context: context)

        _locationService = State(initialValue: location)
        _syncService = State(initialValue: sync)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
                .environment(syncService)
        }
        .modelContainer(container)
    }
}
