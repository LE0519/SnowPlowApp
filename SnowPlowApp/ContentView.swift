import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService

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
        .onAppear {
            DataMaintenance.assignMissingIDs(in: modelContext)
            locationService.configure(context: modelContext)
        }
    }
}
