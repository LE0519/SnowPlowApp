import Foundation
import CoreLocation
import SwiftData
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var isTracking = false
    var authorization: CLAuthorizationStatus = .notDetermined
    var statusText = "GPS is off."

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    private let manager = CLLocationManager()
    private var context: ModelContext?
    private var lastLocation: CLLocation?
    private var enteredAt: [PersistentIdentifier: Date] = [:]
    private var timer: Timer?
    private var askedForAlways = false

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    // MARK: - Start and stop

    func configure(context: ModelContext) {
        self.context = context
        // If the app was reopened during a storm, pick tracking back up.
        if !isTracking, activeStorm() != nil {
            start()
        }
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        statusText = "Starting GPS..."

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysOnce()
            beginUpdates()
        case .authorizedAlways:
            beginUpdates()
        default:
            statusText = "Location access is off. Turn it on in Settings > SnowPlow > Location."
        }
    }

    func stop() {
        isTracking = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        timer?.invalidate()
        timer = nil
        enteredAt = [:]
        lastLocation = nil
        statusText = "GPS is off."
    }

    private func requestAlwaysOnce() {
        if !askedForAlways {
            askedForAlways = true
            manager.requestAlwaysAuthorization()
        }
    }

    private func beginUpdates() {
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false

        // Turning this on without the background mode in the app's settings would crash the app,
        // so check first.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        if modes.contains("location") {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            statusText = "Watching for arrivals..."
        } else {
            statusText = "Watching for arrivals (foreground only: background mode missing from this build)."
        }

        manager.startUpdatingLocation()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    // MARK: - Location delegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        guard isTracking else { return }

        switch authorization {
        case .authorizedWhenInUse:
            requestAlwaysOnce()
            beginUpdates()
        case .authorizedAlways:
            beginUpdates()
        case .denied, .restricted:
            statusText = "Location access is off. Turn it on in Settings > SnowPlow > Location."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        evaluate()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        if code == .locationUnknown {
            return // Temporary. iOS keeps trying.
        }
        statusText = "GPS problem: \(error.localizedDescription)"
    }

    // MARK: - Arrival logic

    private var dwellSeconds: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: "dwellMinutes") as? Int ?? 3
        return TimeInterval(minutes * 60)
    }

    private func activeStorm() -> Storm? {
        guard let context = context else { return nil }
        let storms = (try? context.fetch(FetchDescriptor<Storm>())) ?? []
        return storms.first { $0.isActive }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func evaluate() {
        guard isTracking, let context = context else { return }

        guard let storm = activeStorm() else {
            statusText = "No active storm."
            return
        }
        guard let location = lastLocation else {
            statusText = "Waiting for a GPS fix..."
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else {
            statusText = "GPS signal is weak. Waiting for a better fix..."
            return
        }

        let properties = (try? context.fetch(FetchDescriptor<Property>())) ?? []

        // Find the closest property whose circle we are inside.
        // Once we are inside, the circle is 25% bigger so GPS jitter at the edge does not reset the timer.
        var best: Property?
        var bestDistance = Double.greatestFiniteMagnitude
        for property in properties {
            guard let lat = property.latitude, let lon = property.longitude else { continue }
            let distance = location.distance(from: CLLocation(latitude: lat, longitude: lon))
            let wasInside = enteredAt[property.persistentModelID] != nil
            let limit = wasInside ? property.radiusMeters * 1.25 : property.radiusMeters
            if distance <= limit && distance < bestDistance {
                best = property
                bestDistance = distance
            }
        }

        guard let property = best else {
            enteredAt = [:]
            statusText = "Watching for arrivals. Not at a saved property."
            return
        }

        let id = property.persistentModelID
        enteredAt = enteredAt.filter { $0.key == id }
        if enteredAt[id] == nil {
            enteredAt[id] = Date()
        }

        let customerName = property.customer?.name ?? ""
        let name = customerName.isEmpty ? "(No name)" : customerName

        // Never auto-complete the same property twice in one storm.
        if storm.records.contains(where: { $0.property === property }) {
            statusText = "At \(name): already marked done."
            return
        }

        let elapsed = Date().timeIntervalSince(enteredAt[id] ?? Date())
        if elapsed >= dwellSeconds {
            let driver = UserDefaults.standard.string(forKey: "driverName") ?? "Driver"
            let record = ServiceRecord(driverName: driver, isAutomatic: true)
            context.insert(record)
            record.property = property
            record.storm = storm
            try? context.save()
            statusText = "Marked \(name) done."
        } else {
            statusText = "At \(name): \(formatTime(elapsed)) of \(formatTime(dwellSeconds))"
        }
    }
}
