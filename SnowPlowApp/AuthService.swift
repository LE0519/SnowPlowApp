import Foundation
import SwiftData
import Observation
import FirebaseAuth
import FirebaseFirestore

struct TeamMember: Identifiable {
    let id: String
    let name: String
    let email: String
    let role: String
}

enum DataWipe {
    /// Clears the customers, properties, storms, and jobs stored on this phone.
    static func eraseAll(in context: ModelContext) {
        for record in (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? [] {
            context.delete(record)
        }
        for storm in (try? context.fetch(FetchDescriptor<Storm>())) ?? [] {
            context.delete(storm)
        }
        for property in (try? context.fetch(FetchDescriptor<Property>())) ?? [] {
            context.delete(property)
        }
        for customer in (try? context.fetch(FetchDescriptor<Customer>())) ?? [] {
            context.delete(customer)
        }
        try? context.save()
    }
}

/// Accounts (email and password), teams, join codes, and who can do what.
@MainActor
@Observable
final class AuthService {
    var userID: String?
    var email: String?
    var displayName = ""
    var companyID: String?
    var companyName = ""
    var role: String?
    var joinCode: String?
    var members: [TeamMember] = []
    var message: String?
    var isBusy = false

    var isSignedIn: Bool { userID != nil }
    var inTeam: Bool { companyID != nil }
    var isOwner: Bool { role == "owner" }
    var isDriver: Bool { role == "driver" }
    /// Drivers cannot edit customers or properties. Everyone else (including someone not in a team yet) can.
    var canEditCustomers: Bool { role != "driver" }

    private var context: ModelContext?
    private var sync: SyncService?
    private var location: LocationService?
    private var authHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Start up

    func attach(context: ModelContext, sync: SyncService, location: LocationService) {
        self.context = context
        self.sync = sync
        self.location = location
    }

    func bootstrap() {
        guard FirebaseSetup.configureIfPossible() else { return }
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            let anonymous = user?.isAnonymous ?? false
            let mail = user?.email
            let name = user?.displayName
            Task { @MainActor [weak self] in
                self?.applyAuthChange(uid: uid, anonymous: anonymous, email: mail, name: name)
            }
        }
    }

    private func applyAuthChange(uid: String?, anonymous: Bool, email: String?, name: String?) {
        // Older test builds signed in without an account. Those sign-ins cannot join a team.
        if anonymous {
            try? Auth.auth().signOut()
            return
        }
        userID = uid
        self.email = email
        displayName = name ?? ""
        guard uid != nil else {
            clearTeamState()
            return
        }
        restoreCachedProfile()
        Task { await refreshProfile() }
    }

    // MARK: - Accounts

    func signUp(name: String, email: String, password: String) async {
        guard FirebaseSetup.configureIfPossible() else {
            message = "The Firebase settings file is missing from this build."
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try await change.commitChanges()
            displayName = name
            if !name.isEmpty {
                UserDefaults.standard.set(name, forKey: "driverName")
            }
        } catch {
            message = friendly(error)
        }
    }

    func signIn(email: String, password: String) async {
        guard FirebaseSetup.configureIfPossible() else {
            message = "The Firebase settings file is missing from this build."
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            message = friendly(error)
        }
    }

    func resetPassword(email: String) async {
        guard FirebaseSetup.configureIfPossible() else { return }
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            message = "Type your email address first."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmed)
            message = "A password reset email was sent to \(trimmed)."
        } catch {
            message = friendly(error)
        }
    }

    func signOut() {
        let wasInTeam = inTeam
        sync?.stop()
        location?.stop()
        // Everything is saved in the cloud for a team member, so clear this phone's copy.
        // Someone with no team has nothing in the cloud, so keep their data.
        if wasInTeam, let context = context {
            DataWipe.eraseAll(in: context)
        }
        message = nil
        try? Auth.auth().signOut()
    }

    // MARK: - Teams

    func createTeam(named name: String) async {
        guard let uid = userID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            message = "Give your team a name."
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }

        let db = Firestore.firestore()
        let cid = UUID().uuidString.lowercased()
        let who = ownName()
        do {
            try await db.collection("companies").document(cid).setData([
                "name": trimmed,
                "ownerUID": uid,
                "createdAt": Timestamp(date: Date())
            ])
            try await db.collection("companies").document(cid).collection("members").document(uid).setData([
                "role": "owner",
                "name": who,
                "email": email ?? "",
                "joinedAt": Timestamp(date: Date())
            ])
            let code = try await createUniqueCode(companyID: cid)
            try await db.collection("companies").document(cid).collection("private").document("settings").setData([
                "joinCode": code
            ])
            try await db.collection("users").document(uid).setData([
                "companyID": cid,
                "role": "owner",
                "email": email ?? ""
            ])
            await refreshProfile()
        } catch {
            message = friendly(error)
        }
    }

    func joinTeam(code rawCode: String) async {
        guard let uid = userID else { return }
        let code = rawCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else {
            message = "Type the join code you were sent."
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }

        let db = Firestore.firestore()
        do {
            let codeDoc = try await db.collection("joinCodes").document(code).getDocument()
            guard let cid = codeDoc.data()?["companyID"] as? String else {
                message = "That code was not found. Check it and try again."
                return
            }

            let memberRef = db.collection("companies").document(cid).collection("members").document(uid)
            let existing = try? await memberRef.getDocument()
            if existing?.exists != true {
                try await memberRef.setData([
                    "role": "driver",
                    "name": ownName(),
                    "email": email ?? "",
                    "joinCode": code,
                    "joinedAt": Timestamp(date: Date())
                ])
            }
            try await db.collection("users").document(uid).setData([
                "companyID": cid,
                "role": "driver",
                "email": email ?? ""
            ])

            // This phone should now show only the team's data.
            sync?.stop()
            location?.stop()
            if let context = context {
                DataWipe.eraseAll(in: context)
            }
            await refreshProfile()
        } catch {
            message = friendly(error)
        }
    }

    func newJoinCode() async {
        guard isOwner, let cid = companyID else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        let db = Firestore.firestore()
        do {
            if let old = joinCode {
                try? await db.collection("joinCodes").document(old).delete()
            }
            let code = try await createUniqueCode(companyID: cid)
            try await db.collection("companies").document(cid).collection("private").document("settings").setData([
                "joinCode": code
            ])
            joinCode = code
        } catch {
            message = friendly(error)
        }
    }

    func removeMember(_ memberID: String) async {
        guard isOwner, let cid = companyID else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await Firestore.firestore()
                .collection("companies").document(cid)
                .collection("members").document(memberID).delete()
            await loadMembers()
        } catch {
            message = friendly(error)
        }
    }

    func loadMembers() async {
        guard let cid = companyID else { return }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("companies").document(cid)
                .collection("members").getDocuments()
            let list = snapshot.documents.map { doc -> TeamMember in
                let data = doc.data()
                return TeamMember(
                    id: doc.documentID,
                    name: data["name"] as? String ?? "",
                    email: data["email"] as? String ?? "",
                    role: data["role"] as? String ?? "driver"
                )
            }
            members = list.sorted { first, second in
                let a = (first.role == "owner" ? 0 : 1, first.name)
                let b = (second.role == "owner" ? 0 : 1, second.name)
                return a < b
            }
        } catch {
            message = friendly(error)
        }
    }

    // MARK: - Loading the signed-in person's team

    private func restoreCachedProfile() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "team.uid") == userID,
              let cid = defaults.string(forKey: "team.companyID"),
              let savedRole = defaults.string(forKey: "team.role") else { return }
        companyID = cid
        role = savedRole
        companyName = defaults.string(forKey: "team.name") ?? ""
        startSync()
    }

    func refreshProfile() async {
        guard let uid = userID else { return }
        let db = Firestore.firestore()
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()
            guard let cid = userDoc.data()?["companyID"] as? String, !cid.isEmpty else {
                clearTeamState()
                return
            }
            let memberDoc = try await db.collection("companies").document(cid)
                .collection("members").document(uid).getDocument()
            guard let memberData = memberDoc.data(), let memberRole = memberData["role"] as? String else {
                // The owner removed this person, or the team no longer exists.
                clearTeamState()
                message = "You are not part of a team right now."
                return
            }
            let companyDoc = try await db.collection("companies").document(cid).getDocument()

            companyID = cid
            role = memberRole
            companyName = companyDoc.data()?["name"] as? String ?? ""

            let defaults = UserDefaults.standard
            defaults.set(uid, forKey: "team.uid")
            defaults.set(cid, forKey: "team.companyID")
            defaults.set(memberRole, forKey: "team.role")
            defaults.set(companyName, forKey: "team.name")

            if memberRole == "owner" {
                await loadJoinCode()
                await loadMembers()
            }
            startSync()
        } catch {
            // Offline or a temporary problem: keep using what we already know.
            if companyID == nil {
                message = friendly(error)
            }
        }
    }

    private func loadJoinCode() async {
        guard let cid = companyID else { return }
        do {
            let doc = try await Firestore.firestore()
                .collection("companies").document(cid)
                .collection("private").document("settings").getDocument()
            joinCode = doc.data()?["joinCode"] as? String
        } catch {
            // Not important enough to show.
        }
    }

    private func startSync() {
        guard let cid = companyID else { return }
        sync?.start(companyID: cid, canEditCustomers: role != "driver")
    }

    private func clearTeamState() {
        companyID = nil
        role = nil
        companyName = ""
        joinCode = nil
        members = []
        let defaults = UserDefaults.standard
        for key in ["team.uid", "team.companyID", "team.role", "team.name"] {
            defaults.removeObject(forKey: key)
        }
        sync?.stop()
    }

    // MARK: - Helpers

    private func ownName() -> String {
        if !displayName.isEmpty {
            return displayName
        }
        let saved = UserDefaults.standard.string(forKey: "driverName") ?? ""
        if !saved.isEmpty && saved != "Driver" {
            return saved
        }
        return email?.components(separatedBy: "@").first ?? "Driver"
    }

    private func createUniqueCode(companyID: String) async throws -> String {
        let db = Firestore.firestore()
        var lastError: Error?
        for _ in 0..<5 {
            let code = Self.makeCode()
            do {
                try await db.collection("joinCodes").document(code).setData(["companyID": companyID])
                return code
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NSError(
            domain: "SnowPlow",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not make a join code. Try again."]
        )
    }

    /// Six characters, without letters and numbers that look alike (0/O, 1/I).
    private static func makeCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in characters.randomElement() ?? "A" })
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("permission") {
            return text + " (Check that the new database rules are published in Firebase.)"
        }
        return text
    }
}
