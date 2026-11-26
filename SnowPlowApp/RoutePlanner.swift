import Foundation
import CoreLocation
import SwiftData

struct RouteStop: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let serviceMinutes: Double
    let isLearned: Bool
    let isPriority: Bool
    let deadline: Date?
}

struct PlannedStop: Identifiable {
    let number: Int
    let stop: RouteStop
    let arrival: Date
    let finish: Date
    let travelMinutes: Double
    let lateMinutes: Double

    var id: PersistentIdentifier { stop.id }
}

struct PlannedRoute: Identifiable {
    let id: Int
    let stops: [PlannedStop]

    var finish: Date? { stops.last?.finish }
    var lateCount: Int { stops.filter { $0.lateMinutes > 0 }.count }
    var travelMinutes: Double { stops.reduce(0) { $0 + $1.travelMinutes } }
    var serviceMinutes: Double { stops.reduce(0) { $0 + $1.stop.serviceMinutes } }
}

/// How a storm's size changes the time at each property.
/// Light snow takes about the same time whether it is 1 inch or 2. Above a threshold,
/// every extra inch adds a share of the property's normal time.
struct SnowCurve {
    let threshold: Double
    let growth: Double
    let isLearned: Bool
    let observations: Int

    func factor(at inches: Double) -> Double {
        if inches <= threshold {
            return 1
        }
        return 1 + growth * (inches - threshold)
    }

    var summary: String {
        let percent = Int((growth * 100).rounded())
        let source = isLearned
            ? "learned from \(observations) heavy-snow visits"
            : "a guess until there are heavier storms to learn from"
        return "Snow up to \(threshold.formatted()) in takes about the same time at each property. Each extra inch adds about \(percent)% (\(source))."
    }
}

struct PlowModel {
    let curve: SnowCurve
    let baseByProperty: [PersistentIdentifier: Double]
    let fleetBase: Double?

    /// Minutes at this property in light snow, if the app has timed it.
    func lightSnowMinutes(for property: Property) -> Double? {
        baseByProperty[property.persistentModelID]
    }

    func estimate(for property: Property, inches: Double, defaultMinutes: Double) -> (minutes: Double, learned: Bool) {
        let factor = curve.factor(at: max(inches, 0))
        if let own = baseByProperty[property.persistentModelID] {
            return (max(2, own * factor), true)
        }
        if let fleet = fleetBase {
            return (max(2, fleet * factor), false)
        }
        return (max(2, defaultMinutes * factor), false)
    }
}

/// Works out how long each property is expected to take, from what the app has learned.
enum PlowEstimator {
    struct Sample {
        let minutes: Double
        let inches: Double?
    }

    /// Only visits with both an arrival and a departure time count. Very short and very long
    /// visits are ignored, since they are usually GPS glitches or a stop for something else.
    static func samples(for property: Property) -> [Sample] {
        property.records.compactMap { record in
            guard let arrived = record.arrivedAt, let departed = record.departedAt else { return nil }
            let minutes = departed.timeIntervalSince(arrived) / 60
            guard minutes >= 1, minutes <= 180 else { return nil }
            return Sample(minutes: minutes, inches: record.storm?.snowInches)
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Learns two things from recorded visits: how long each property takes in light snow,
    /// and how much longer heavier storms take. Until there is enough data, the settings are used.
    static func buildModel(properties: [Property]) -> PlowModel {
        let defaults = UserDefaults.standard
        let threshold = (defaults.object(forKey: "snowLightInches") as? Double) ?? 2.0
        let defaultGrowth = Double((defaults.object(forKey: "snowExtraPercent") as? Int) ?? 12) / 100

        // 1. Time in light snow, for properties that have been timed in light snow.
        var lightBase: [PersistentIdentifier: Double] = [:]
        for property in properties {
            var light: [Double] = []
            for sample in samples(for: property) {
                if let inches = sample.inches, inches > 0, inches <= threshold {
                    light.append(sample.minutes)
                }
            }
            if let base = median(light) {
                lightBase[property.persistentModelID] = base
            }
        }

        // 2. How much longer heavy storms take, from properties timed in both light and heavy snow.
        var growthValues: [Double] = []
        for property in properties {
            guard let base = lightBase[property.persistentModelID], base > 0 else { continue }
            for sample in samples(for: property) {
                guard let inches = sample.inches, inches > threshold else { continue }
                let extra = sample.minutes / base - 1
                growthValues.append(extra / (inches - threshold))
            }
        }
        var growth = defaultGrowth
        var learned = false
        if growthValues.count >= 3, let value = median(growthValues) {
            growth = min(max(value, 0), 0.5)
            learned = true
        }
        let curve = SnowCurve(
            threshold: threshold,
            growth: growth,
            isLearned: learned,
            observations: growthValues.count
        )

        // 3. A light-snow time for every property that has been timed at all.
        var base: [PersistentIdentifier: Double] = [:]
        for property in properties {
            let id = property.persistentModelID
            if let known = lightBase[id] {
                base[id] = known
                continue
            }
            // Only heavy-snow visits (or visits with no snowfall recorded): scale back to light snow.
            var scaled: [Double] = []
            for sample in samples(for: property) {
                if let inches = sample.inches, inches > threshold {
                    scaled.append(sample.minutes / curve.factor(at: inches))
                } else if sample.inches == nil {
                    scaled.append(sample.minutes)
                }
            }
            if let value = median(scaled) {
                base[id] = value
            }
        }

        return PlowModel(curve: curve, baseByProperty: base, fleetBase: median(Array(base.values)))
    }
}

/// Suggests an order for the remaining properties that protects the priority deadlines.
enum RoutePlanner {
    /// Driving time from straight-line distance. Roads are longer than straight lines, so add 40%.
    static func travelMinutes(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, mph: Double) -> Double {
        let first = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let second = CLLocation(latitude: b.latitude, longitude: b.longitude)
        let meters = first.distance(from: second) * 1.4
        let metersPerMinute = max(mph, 1) * 26.8224
        return meters / metersPerMinute
    }

    static func plan(stops: [RouteStop],
                     start: CLLocationCoordinate2D?,
                     startTime: Date,
                     mph: Double) -> [PlannedStop] {
        var remaining = stops
        var position = start
        var clock = startTime
        var result: [PlannedStop] = []

        while !remaining.isEmpty {
            let index = nextIndex(remaining: remaining, position: position, clock: clock, mph: mph)
            let stop = remaining.remove(at: index)

            var travel = 0.0
            if let from = position {
                travel = travelMinutes(from: from, to: stop.coordinate, mph: mph)
            }
            let arrival = clock.addingTimeInterval(travel * 60)
            let finish = arrival.addingTimeInterval(stop.serviceMinutes * 60)

            var late = 0.0
            if let deadline = stop.deadline, finish > deadline {
                late = finish.timeIntervalSince(deadline) / 60
            }

            result.append(PlannedStop(
                number: result.count + 1,
                stop: stop,
                arrival: arrival,
                finish: finish,
                travelMinutes: travel,
                lateMinutes: late
            ))
            position = stop.coordinate
            clock = finish
        }
        return result
    }

    /// How many minutes late the stops with deadlines would be if we went straight to them, earliest deadline first.
    private static func totalLateness(of stops: [RouteStop],
                                      from position: CLLocationCoordinate2D?,
                                      at start: Date,
                                      mph: Double) -> Double {
        let ordered = stops.sorted {
            ($0.deadline ?? Date.distantFuture) < ($1.deadline ?? Date.distantFuture)
        }
        var clock = start
        var here = position
        var late = 0.0
        for stop in ordered {
            if let from = here {
                clock = clock.addingTimeInterval(travelMinutes(from: from, to: stop.coordinate, mph: mph) * 60)
            }
            clock = clock.addingTimeInterval(stop.serviceMinutes * 60)
            if let deadline = stop.deadline, clock > deadline {
                late += clock.timeIntervalSince(deadline) / 60
            }
            here = stop.coordinate
        }
        return late
    }

    private static func nextIndex(remaining: [RouteStop],
                                  position: CLLocationCoordinate2D?,
                                  clock: Date,
                                  mph: Double) -> Int {
        func travel(to stop: RouteStop) -> Double {
            guard let from = position else { return 0 }
            return travelMinutes(from: from, to: stop.coordinate, mph: mph)
        }

        let deadlineStops = remaining.filter { $0.deadline != nil }

        if !deadlineStops.isEmpty {
            // The most urgent stop is the one with the earliest deadline.
            var urgentIndex = 0
            var urgentDeadline = Date.distantFuture
            for (index, stop) in remaining.enumerated() {
                if let deadline = stop.deadline, deadline < urgentDeadline {
                    urgentDeadline = deadline
                    urgentIndex = index
                }
            }

            // Could we do another property on the way without making any deadline later?
            let baseline = totalLateness(of: deadlineStops, from: position, at: clock, mph: mph)
            var fillerIndex: Int?
            var fillerCost = Double.greatestFiniteMagnitude
            for (index, stop) in remaining.enumerated() where stop.deadline == nil {
                let driving = travel(to: stop)
                let finish = clock.addingTimeInterval((driving + stop.serviceMinutes) * 60)
                let late = totalLateness(of: deadlineStops, from: stop.coordinate, at: finish, mph: mph)
                if late <= baseline + 0.5 {
                    let cost = driving - (stop.isPriority ? 5 : 0)
                    if cost < fillerCost {
                        fillerCost = cost
                        fillerIndex = index
                    }
                }
            }
            return fillerIndex ?? urgentIndex
        }

        // No deadlines left: closest first, with a small preference for priority properties.
        var bestIndex = 0
        var bestCost = Double.greatestFiniteMagnitude
        for (index, stop) in remaining.enumerated() {
            let cost = travel(to: stop) - (stop.isPriority ? 5 : 0)
            if cost < bestCost {
                bestCost = cost
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Splits the properties between trucks by area, so each truck gets a group that sits together.
    static func cluster(_ stops: [RouteStop], into count: Int) -> [[RouteStop]] {
        guard count > 1, stops.count > count else { return [stops] }

        func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let dx = (a.longitude - b.longitude) * cos(a.latitude * Double.pi / 180)
            let dy = a.latitude - b.latitude
            return dx * dx + dy * dy
        }

        let meanLat = stops.reduce(0.0) { $0 + $1.coordinate.latitude } / Double(stops.count)
        let meanLon = stops.reduce(0.0) { $0 + $1.coordinate.longitude } / Double(stops.count)
        let mean = CLLocationCoordinate2D(latitude: meanLat, longitude: meanLon)

        // Start the groups far apart from each other.
        var centers: [CLLocationCoordinate2D] = []
        if let first = stops.max(by: { distance($0.coordinate, mean) < distance($1.coordinate, mean) }) {
            centers.append(first.coordinate)
        }
        while centers.count < count {
            let next = stops.max { a, b in
                let da = centers.map { distance(a.coordinate, $0) }.min() ?? 0
                let db = centers.map { distance(b.coordinate, $0) }.min() ?? 0
                return da < db
            }
            if let next = next {
                centers.append(next.coordinate)
            } else {
                break
            }
        }

        var assignment = [Int](repeating: 0, count: stops.count)
        for _ in 0..<12 {
            for (i, stop) in stops.enumerated() {
                var best = 0
                var bestDistance = Double.greatestFiniteMagnitude
                for (c, center) in centers.enumerated() {
                    let d = distance(stop.coordinate, center)
                    if d < bestDistance {
                        bestDistance = d
                        best = c
                    }
                }
                assignment[i] = best
            }
            for c in centers.indices {
                let members = stops.indices.filter { assignment[$0] == c }
                if members.isEmpty { continue }
                let lat = members.reduce(0.0) { $0 + stops[$1].coordinate.latitude } / Double(members.count)
                let lon = members.reduce(0.0) { $0 + stops[$1].coordinate.longitude } / Double(members.count)
                centers[c] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }

        var groups = [[RouteStop]](repeating: [], count: centers.count)
        for (i, stop) in stops.enumerated() {
            groups[assignment[i]].append(stop)
        }
        return groups.filter { !$0.isEmpty }
    }
}
