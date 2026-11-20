import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CustomerListView()
                .tabItem {
                    Label("Customers", systemImage: "person.2")
                }

            PropertyMapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
        }
    }
}
