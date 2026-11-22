import Foundation
import CoreLocation
import SwiftData
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var isTracking = false
    var authorization: CLAuthorizationStatus = .notDetermined
    var statusText = "GPS is off."

    // Shown live on the Storm screen while you are at a property.
    var arrivedName: String?
    var arrivedAt: Date?
    var arrivedIsDone = false

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    private let manager = CLLocationManager()
    private var context: ModelContext?
    private var lastLocation: CLLocation?
    private var lastRegionRefresh: CLLocation?
    private var watchedCount = 0
    private var enteredAt: [PersistentIdentifier: Date] = [:]
    private var timer: Timer?
    private var askedForAlways = false
    private let maxRegions = 20

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    // MARK: - Start and stop

    func configure(context: ModelContext) {
        self.context = context
        // If the app was reopened (or restarted by iOS) during a storm, pick tracking back up.
        if !isTracking, activeStorm() != nil {
            start()
        }
    }

    /// Lets the map show your location dot even when no storm is running.
    func requestPermissionIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        setStatus("Starting GPS...")

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
        manager.stopMonitoringSignificantLocationChanges()
        stopRegions()
        manager.allowsBackgroundLocationUpdates = false
        timer?.invalidate()
        timer = nil
        enteredAt = [:]
        lastLocation = nil
        arrivedName = nil
        arrivedAt = nil
        arrivedIsDone = false
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
            setStatus("Watching for arrivals...")
        } else {
            setStatus("Watching for arrivals (foreground only: background mode missing from this build).")
        }

        manager.startUpdatingLocation()

        // These two let iOS restart the app if it gets closed during a storm.
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        refreshRegions(around: manager.location)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
    }

    // MARK: - Restart watching (the 20 closest unfinished properties)

    private func refreshRegions(around location: CLLocation?) {
        guard isTracking, let context = context else { return }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        guard let storm = activeStorm() else {
            stopRegions()
            return
        }

        let properties = (try? context.fetch(FetchDescriptor<Property>())) ?? []
        var candidates: [(id: String, center: CLLocationCoordinate2D, radius: Double, distance: Double)] = []
        for property in properties {
            guard let lat = property.latitude, let lon = property.longitude,
                  let uuid = property.uuid else { continue }
            // Properties already done in this storm do not need to wake the app.
            if storm.records.contains(where: { $0.property === property }) { continue }
            let distance = location?.distance(from: CLLocation(latitude: lat, longitude: lon)) ?? 0
            candidates.append((
                id: uuid.uuidString,
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                radius: property.radiusMeters,
                distance: distance
            ))
        }
        candidates.sort { $0.distance < $1.distance }
        let chosen = Array(candidates.prefix(maxRegions))
        let chosenIDs = Set(chosen.map { $0.id })

        for region in manager.monitoredRegions where !chosenIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }

        let alreadyWatching = Set(manager.monitoredRegions.map { $0.identifier })
        let largest = manager.maximumRegionMonitoringDistance
        let cap = largest > 0 ? largest : 5000
        for item in chosen where !alreadyWatching.contains(item.id) {
            // iOS is unreliable with very small regions, so use at least 100 m.
            let radius = min(max(item.radius, 100), cap)
            let region = CLCircularRegion(center: item.center, radius: radius, identifier: item.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }

        watchedCount = chosen.count
        lastRegionRefresh = location
    }

    private func stopRegions() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        watchedCount = 0
        lastRegionRefresh = nil
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

        // Swap which 20 properties iOS watches once we have moved a good distance.
        if let current = lastLocation {
            if let previous = lastRegionRefresh {
                if current.distance(from: previous) > 1000 {
                    refreshRegions(around: current)
                }
            } else {
                refreshRegions(around: current)
            }
        }
        evaluate()
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        // iOS woke the app because we drove into a property's area. Make sure full GPS watching is on,
        // and start the arrival timer from now.
        if !isTracking, activeStorm() != nil {
            start()
        }
        if let context = context, let uuid = UUID(uuidString: region.identifier) {
            let properties = (try? context.fetch(FetchDescriptor<Property>())) ?? []
            if let property = properties.first(where: { $0.uuid == uuid }),
               enteredAt[property.persistentModelID] == nil {
                enteredAt[property.persistentModelID] = Date()
            }
        }
        manager.startUpdatingLocation()
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

    /// Sets the status line and adds helpful notes about restart watching.
    private func setStatus(_ text: String) {
        var full = text
        if isTracking && watchedCount > 0 {
            full += " Restart watch: \(watchedCount)."
        }
        if isTracking && authorization == .authorizedWhenInUse {
            full += " Tip: set Location to Always in iPhone Settings so the app can restart itself."
        }
        statusText = full
    }

    private func evaluate() {
        guard isTracking, let context = context else { return }

        guard let storm = activeStorm() else {
            // The storm was ended (maybe from another phone), so stop using GPS and battery.
            stop()
            return
        }
        guard let location = lastLocation else {
            setStatus("Waiting for a GPS fix...")
            return
        }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else {
            setStatus("GPS signal is weak. Waiting for a better fix...")
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
            arrivedName = nil
            arrivedAt = nil
            arrivedIsDone = false
            setStatus("Watching for arrivals. Not at a saved property.")
            return
        }

        let id = property.persistentModelID
        enteredAt = enteredAt.filter { $0.key == id }
        if enteredAt[id] == nil {
            enteredAt[id] = Date()
        }

        let customerName = property.customer?.name ?? ""
        let name = customerName.isEmpty ? "(No name)" : customerName

        arrivedName = name
        arrivedAt = enteredAt[id]

        // Never auto-complete the same property twice in one storm.
        if storm.records.contains(where: { $0.property === property }) {
            arrivedIsDone = true
            setStatus("At \(name): already marked done.")
            return
        }
        arrivedIsDone = false

        let elapsed = Date().timeIntervalSince(enteredAt[id] ?? Date())
        if elapsed >= dwellSeconds {
            let driver = UserDefaults.standard.string(forKey: "driverName") ?? "Driver"
            let record = ServiceRecord(driverName: driver, isAutomatic: true)
            context.insert(record)
            record.property = property
            record.storm = storm
            try? context.save()
            arrivedIsDone = true
            refreshRegions(around: location)
            setStatus("Marked \(name) done.")
        } else {
            setStatus("At \(name).")
        }
    }
}
