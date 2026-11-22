import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @AppStorage("driverName") private var driverName = "Driver"
    @AppStorage("dwellMinutes") private var dwellMinutes = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AccountView()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Team and account", systemImage: "person.badge.key")
                            Text(teamSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Team")
                } footer: {
                    Text("Sign in and join a team to share customers and jobs between phones. Your location is never sent.")
                }

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

    private var teamSummary: String {
        if auth.inTeam {
            return "\(auth.companyName) (\(auth.isOwner ? "owner" : "driver")). \(syncService.statusText)"
        }
        if auth.isSignedIn {
            return "Signed in, not in a team yet"
        }
        return "Not signed in"
    }
}
