import Foundation
import FirebaseCore
import FirebaseAuth

enum FirebaseSetup {
    /// Starts Firebase if the settings file is in the app. Returns false if it is missing.
    static func configureIfPossible() -> Bool {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return false
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}

enum CurrentUser {
    /// The signed-in person's ID, or nil when nobody is signed in (or Firebase is not set up).
    static var uid: String? {
        guard FirebaseApp.app() != nil else { return nil }
        return Auth.auth().currentUser?.uid
    }
}
