import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @AppStorage("driverName") private var driverName = "Driver"
    @AppStorage("dwellMinutes") private var dwellMinutes = 3
    @AppStorage("routeDefaultMinutes") private var routeDefaultMinutes = 10
    @AppStorage("routeSpeedMPH") private var routeSpeedMPH = 20
    @AppStorage("routeWinterPercent") private var routeWinterPercent = 150

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

                Section {
                    Stepper("Guess per property: \(routeDefaultMinutes) min", value: $routeDefaultMinutes, in: 3...60)
                    Stepper("Average driving speed: \(routeSpeedMPH) mph", value: $routeSpeedMPH, in: 10...45)
                    Stepper("Winter slowdown: \(routeWinterPercent)%", value: $routeWinterPercent, in: 100...300, step: 10)
                } header: {
                    Text("Route planning")
                } footer: {
                    Text("The guess per property is used until the planner has learned real times from your storms. The driving speed is for the quick straight-line estimate. Winter slowdown stretches Apple's normal road drive times, since they don't know about snow. 150% means a 10 minute drive is planned as 15.")
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
