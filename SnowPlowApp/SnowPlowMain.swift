import SwiftUI
import SwiftData

@main
struct SnowPlowMain: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Customer.self, Property.self])
    }
}
