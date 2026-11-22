import SwiftUI
import SwiftData

@main
struct SnowPlowMain: App {
    private let container: ModelContainer
    @State private var locationService: LocationService
    @State private var syncService: SyncService
    @State private var authService: AuthService

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Customer.self, Property.self, Storm.self, ServiceRecord.self, Shift.self
            )
        } catch {
            fatalError("Could not open the SnowPlow database: \(error)")
        }
        self.container = container

        // These are set up here, not on a screen, so they also work when iOS restarts
        // the app in the background during a storm.
        // Firebase is started first so the signed-in person is known right away.
        _ = FirebaseSetup.configureIfPossible()

        let context = container.mainContext
        DataMaintenance.assignMissingIDs(in: context)

        let location = LocationService()
        location.configure(context: context)

        let sync = SyncService()
        sync.configure(context: context)

        let auth = AuthService()
        auth.attach(context: context, sync: sync, location: location)
        auth.bootstrap()

        _locationService = State(initialValue: location)
        _syncService = State(initialValue: sync)
        _authService = State(initialValue: auth)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationService)
                .environment(syncService)
                .environment(authService)
        }
        .modelContainer(container)
    }
}
