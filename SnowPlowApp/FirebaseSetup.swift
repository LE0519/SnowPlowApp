import Foundation
import FirebaseCore

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
