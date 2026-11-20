import SwiftUI

struct SettingsView: View {
    @AppStorage("driverName") private var driverName = "Driver"
    @AppStorage("dwellMinutes") private var dwellMinutes = 3

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

                Section {
                    Stepper("Time at property: \(dwellMinutes) min", value: $dwellMinutes, in: 1...15)
                } header: {
                    Text("Automatic check-off")
                } footer: {
                    Text("A property is checked off automatically after you stay inside its circle this long. Use 1 minute while testing.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
