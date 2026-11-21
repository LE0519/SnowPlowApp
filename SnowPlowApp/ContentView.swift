import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncService.self) private var syncService

    var body: some View {
        TabView {
            StormView()
                .tabItem {
                    Label("Storm", systemImage: "snowflake")
                }

            CustomerListView()
                .tabItem {
                    Label("Customers", systemImage: "person.2")
                }

            PropertyMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                syncService.syncNow()
            }
        }
    }
}
