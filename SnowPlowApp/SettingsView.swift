import SwiftUI

struct SettingsView: View {
    @Environment(SyncService.self) private var syncService
    @AppStorage("driverName") private var driverName = "Driver"
    @AppStorage("dwellMinutes") private var dwellMinutes = 3
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false

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

                Section {
                    Toggle("Sync with the cloud", isOn: $cloudSyncEnabled)
                    if cloudSyncEnabled {
                        Text(syncService.statusText)
                            .font(.subheadline)
                        if !syncService.detailText.isEmpty {
                            Text(syncService.detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Sync now") {
                            syncService.syncNow()
                        }
                    }
                } header: {
                    Text("Cloud sync")
                } footer: {
                    Text("Copies your customers, properties, and completed jobs to the cloud so other phones can see them. It works offline and catches up when you have signal. Your location is never sent.")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: cloudSyncEnabled) { _, isOn in
                if isOn {
                    syncService.start()
                } else {
                    syncService.stop()
                }
            }
        }
    }
}
