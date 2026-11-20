import SwiftUI

struct SettingsView: View {
    @AppStorage("driverName") private var driverName = "Driver"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $driverName)
                } header: {
                    Text("Driver")
                } footer: {
                    Text("This name is saved on every property you complete.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
