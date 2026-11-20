import SwiftUI

struct ContentView: View {
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
    }
}
