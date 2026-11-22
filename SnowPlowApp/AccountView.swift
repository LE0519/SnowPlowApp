import SwiftUI

struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService

    @State private var mode = 0
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var teamName = ""
    @State private var joinCode = ""
    @State private var confirmJoin = false
    @State private var confirmSignOut = false
    @State private var memberToRemove: TeamMember?

    var body: some View {
        Form {
            if !auth.isSignedIn {
                signedOutSections
            } else if !auth.inTeam {
                noTeamSections
            } else {
                teamSections
            }

            if let message = auth.message {
                Section {
                    Text(message)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Team and account")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(auth.isBusy)
        .overlay {
            if auth.isBusy {
                ProgressView()
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Join this team?", isPresented: $confirmJoin) {
            Button("Join", role: .destructive) {
                Task { await auth.joinTeam(code: joinCode) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The customers and storms on this phone will be replaced with your team's.")
        }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(auth.inTeam
                 ? "This clears your team's customers and storms from this phone. They stay safe in the cloud. Anything that has not synced yet will be lost, so tap Sync now first."
                 : "You can sign back in any time.")
        }
        .alert(
            "Remove \(memberToRemove?.name ?? "this person")?",
            isPresented: Binding(
                get: { memberToRemove != nil },
                set: { if !$0 { memberToRemove = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task { await auth.removeMember(member.id) }
                }
                memberToRemove = nil
            }
            Button("Cancel", role: .cancel) {
                memberToRemove = nil
            }
        } message: {
            Text("They will stop receiving your team's data. Their phone keeps the copy it already has.")
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signedOutSections: some View {
        Section {
            Picker("Mode", selection: $mode) {
                Text("Sign in").tag(0)
                Text("Create account").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == 1 {
                TextField("Your name", text: $name)
            }
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            SecureField("Password (6 or more characters)", text: $password)

            Button(mode == 0 ? "Sign in" : "Create account") {
                Task {
                    if mode == 0 {
                        await auth.signIn(email: email, password: password)
                    } else {
                        await auth.signUp(name: name, email: email, password: password)
                    }
                }
            }
            .disabled(email.isEmpty || password.count < 6 || (mode == 1 && name.isEmpty))

            if mode == 0 {
                Button("Forgot password?") {
                    Task { await auth.resetPassword(email: email) }
                }
            }
        } footer: {
            Text("An account lets you share customers and jobs with your team. The app still works on this phone without one.")
        }
    }

    // MARK: - Signed in, not in a team

    @ViewBuilder
    private var noTeamSections: some View {
        Section("Signed in as") {
            Text(auth.email ?? "")
        }

        Section {
            TextField("Team name (your company)", text: $teamName)
            Button("Create team") {
                Task { await auth.createTeam(named: teamName) }
            }
            .disabled(teamName.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Start a team (owner)")
        } footer: {
            Text("The customers and properties on this phone are copied to the team. Needs internet.")
        }

        Section {
            TextField("Join code", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Join team") {
                confirmJoin = true
            }
            .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Join a team (driver)")
        } footer: {
            Text("Joining replaces the customers on this phone with your team's. Needs internet.")
        }

        Section {
            Button("Sign out", role: .destructive) {
                confirmSignOut = true
            }
        }
    }

    // MARK: - In a team

    private var inviteText: String {
        "Join \(auth.companyName) on SnowPlow. Open the app, go to Settings, then Team and account, create an account, tap Join team, and enter this code: \(auth.joinCode ?? "")"
    }

    @ViewBuilder
    private var teamSections: some View {
        Section("Team") {
            LabeledContent("Team", value: auth.companyName)
            LabeledContent("Your role", value: auth.isOwner ? "Owner" : "Driver")
            LabeledContent("Signed in as", value: auth.email ?? "")
        }

        Section("Sync") {
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

        if auth.isOwner {
            Section {
                LabeledContent("Join code", value: auth.joinCode ?? "...")
                if auth.joinCode != nil {
                    ShareLink(item: inviteText) {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Make a new code") {
                    Task { await auth.newJoinCode() }
                }
            } header: {
                Text("Invite drivers")
            } footer: {
                Text("Anyone with the code can join as a driver. Make a new code to stop the old one working.")
            }

            Section("People") {
                ForEach(auth.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name.isEmpty ? member.email : member.name)
                            if !member.email.isEmpty {
                                Text(member.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(member.role == "owner" ? "Owner" : "Driver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if member.role != "owner" {
                            Button("Remove", role: .destructive) {
                                memberToRemove = member
                            }
                        }
                    }
                }
                Button("Refresh list") {
                    Task { await auth.loadMembers() }
                }
            }
        }

        Section {
            Button("Sign out", role: .destructive) {
                confirmSignOut = true
            }
        }
    }
}
