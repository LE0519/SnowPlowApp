import SwiftUI
import SwiftData
import MapKit
import CoreLocation

private struct LegKey: Hashable {
    let from: PersistentIdentifier?
    let to: PersistentIdentifier
}

private struct RoadLeg {
    let coordinates: [CLLocationCoordinate2D]
    let seconds: TimeInterval
    let meters: Double
}

private struct MapSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let isRoad: Bool
    let color: Color
}

extension MKPolyline {
    var coordinateList: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

struct RouteView: View {
    @Environment(LocationService.self) private var locationService
    @Query private var properties: [Property]
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @AppStorage("routeDefaultMinutes") private var defaultMinutes = 10
    @AppStorage("routeSpeedMPH") private var speedMPH = 20
    @AppStorage("routeWinterPercent") private var winterPercent = 150

    @State private var inchesText = ""
    @State private var trucks = 1
    @State private var fromMyLocation = true
    @State private var routes: [PlannedRoute] = []
    @State private var learnedCount = 0
    @State private var totalCount = 0
    @State private var planStart = Date()
    @State private var startCoordinate: CLLocationCoordinate2D?
    @State private var roadLegs: [LegKey: RoadLeg] = [:]
    @State private var failedLegs: Set<LegKey> = []
    @State private var loadingText: String?

    private let palette: [Color] = [.blue, .green, .purple, .red]
    private let colorNames = ["Blue", "Green", "Purple", "Red"]

    private func color(for routeID: Int) -> Color {
        palette[(routeID - 1) % palette.count]
    }

    private func truckName(_ routeID: Int) -> String {
        colorNames[(routeID - 1) % colorNames.count] + " truck"
    }

    private var rebuildKey: String {
        "\(inchesText)|\(trucks)|\(fromMyLocation)|\(properties.count)|\(defaultMinutes)|\(speedMPH)"
    }

    /// Changes whenever the order of any truck's stops changes, so road routes get reloaded.
    private var legSignature: String {
        routes
            .map { route in route.stops.map { "\($0.stop.id.hashValue)" }.joined(separator: ",") }
            .joined(separator: "|") + "|\(startCoordinate != nil)"
    }

    /// The planned routes with drive times replaced by real road times wherever Apple has provided them.
    private var timedRoutes: [PlannedRoute] {
        let factor = Double(winterPercent) / 100
        return routes.map { route in
            var clock = planStart
            var previous: RouteStop?
            var result: [PlannedStop] = []
            for planned in route.stops {
                var travel = planned.travelMinutes
                let key = LegKey(from: previous?.id, to: planned.stop.id)
                if let leg = roadLegs[key] {
                    travel = leg.seconds / 60 * factor
                }
                let arrival = clock.addingTimeInterval(travel * 60)
                let finish = arrival.addingTimeInterval(planned.stop.serviceMinutes * 60)
                var late = 0.0
                if let deadline = planned.stop.deadline, finish > deadline {
                    late = finish.timeIntervalSince(deadline) / 60
                }
                result.append(PlannedStop(
                    number: planned.number,
                    stop: planned.stop,
                    arrival: arrival,
                    finish: finish,
                    travelMinutes: travel,
                    lateMinutes: late
                ))
                previous = planned.stop
                clock = finish
            }
            return PlannedRoute(id: route.id, stops: result)
        }
    }

    private var lateTotal: Int {
        timedRoutes.reduce(0) { $0 + $1.lateCount }
    }

    private var segments: [MapSegment] {
        var list: [MapSegment] = []
        for route in routes {
            var previous: RouteStop?
            for (index, planned) in route.stops.enumerated() {
                let key = LegKey(from: previous?.id, to: planned.stop.id)
                if let leg = roadLegs[key] {
                    list.append(MapSegment(
                        id: "\(route.id)-\(index)",
                        coordinates: leg.coordinates,
                        isRoad: true,
                        color: color(for: route.id)
                    ))
                } else {
                    var from: CLLocationCoordinate2D?
                    if let previous = previous {
                        from = previous.coordinate
                    } else {
                        from = startCoordinate
                    }
                    if let from = from {
                        list.append(MapSegment(
                            id: "\(route.id)-\(index)",
                            coordinates: [from, planned.stop.coordinate],
                            isRoad: false,
                            color: color(for: route.id)
                        ))
                    }
                }
                previous = planned.stop
            }
        }
        return list
    }

    // MARK: - Screen

    var body: some View {
        List {
            Section {
                TextField("Expected snowfall (inches)", text: $inchesText)
                    .keyboardType(.decimalPad)
                Stepper("Trucks: \(trucks)", value: $trucks, in: 1...4)
                Toggle("Start from my location", isOn: $fromMyLocation)
                Button("Rebuild route") {
                    rebuild()
                }
            } header: {
                Text("Plan")
            } footer: {
                Text(planFooter)
            }

            if totalCount == 0 {
                Section {
                    Text("Nothing to plan yet. Add properties with map locations, or finish a storm's properties to start fresh.")
                        .foregroundStyle(.secondary)
                }
            } else {
                summarySection
                mapSection

                ForEach(timedRoutes) { route in
                    Section {
                        if let first = route.stops.first {
                            Button {
                                openDirections(to: first.stop)
                            } label: {
                                Label("Navigate to stop 1 in Apple Maps", systemImage: "location.north.circle.fill")
                                    .font(.headline)
                            }
                            .tint(color(for: route.id))
                        }
                        ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, planned in
                            stopRow(
                                planned,
                                previous: index > 0 ? route.stops[index - 1].stop : nil,
                                tint: color(for: route.id)
                            )
                        }
                        ShareLink(item: shareText(route)) {
                            Label("Share this route", systemImage: "square.and.arrow.up")
                        }
                    } header: {
                        routeHeader(route)
                    }
                }
            }
        }
        .navigationTitle("Route planner")
        .onAppear {
            if inchesText.isEmpty {
                if let last = storms.first(where: { ($0.snowInches ?? 0) > 0 }), let inches = last.snowInches {
                    inchesText = inches == inches.rounded() ? String(Int(inches)) : String(inches)
                } else {
                    inchesText = "3"
                }
            }
            rebuild()
        }
        .onChange(of: rebuildKey) { _, _ in
            rebuild()
        }
        .task(id: legSignature) {
            await loadRoadLegs()
        }
    }

    private var planFooter: String {
        var text = "Uses your own recorded times for \(learnedCount) of \(totalCount) properties"
        if totalCount > learnedCount {
            text += " and a guess of \(defaultMinutes) minutes for the rest (change this in Settings)"
        }
        text += "."
        return text
    }

    // MARK: - Pieces

    @ViewBuilder
    private var summarySection: some View {
        Section {
            if lateTotal == 0 {
                Label("Every priority deadline looks reachable.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("\(lateTotal) priority \(lateTotal == 1 ? "stop" : "stops") would likely be late. Try another truck, or move the deadline.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            ForEach(timedRoutes) { route in
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: route.id))
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(truckName(route.id))
                            .font(.headline)
                        Text("\(route.stops.count) \(route.stops.count == 1 ? "stop" : "stops"), done around \(route.finish.map { timeText($0) } ?? "-")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if route.lateCount > 0 {
                        Text("\(route.lateCount) late")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("Summary")
        } footer: {
            Text(trucks > 1
                 ? "With more than one truck, the planner splits the properties into areas, so each truck gets a group that sits close together. The colors are only labels. You decide which driver takes which color."
                 : "Add trucks above to split the properties into areas, one color per truck.")
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        Section {
            Map {
                UserAnnotation()
                ForEach(segments) { segment in
                    if segment.isRoad {
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(segment.color, lineWidth: 4)
                    } else {
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(segment.color, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    }
                }
                ForEach(routes) { route in
                    ForEach(route.stops) { planned in
                        Annotation("", coordinate: planned.stop.coordinate) {
                            Text("\(planned.number)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(color(for: route.id)))
                                .overlay(
                                    Circle().stroke(planned.stop.isPriority ? Color.orange : Color.white, lineWidth: 2)
                                )
                        }
                    }
                }
            }
            .frame(height: 300)
            .listRowInsets(EdgeInsets())

            if let loadingText = loadingText {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(loadingText)
                        .font(.caption)
                }
            }
        } footer: {
            Text("Solid lines follow real roads. Dashed lines are straight-line estimates that have not loaded yet, or could not be found. Road routes need internet.")
        }
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func routeHeader(_ route: PlannedRoute) -> some View {
        let finishText = route.finish.map { timeText($0) } ?? "-"
        let total = Int(route.serviceMinutes + route.travelMinutes)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color(for: route.id))
                    .frame(width: 12, height: 12)
                Text("\(truckName(route.id)): \(route.stops.count) stops")
                    .font(.headline)
                    .foregroundStyle(color(for: route.id))
            }
            Text("About \(total / 60) h \(total % 60) m of work, done around \(finishText)")
                .font(.caption)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func stopRow(_ planned: PlannedStop, previous: RouteStop?, tint: Color) -> some View {
        let key = LegKey(from: previous?.id, to: planned.stop.id)
        let leg = roadLegs[key]
        HStack(alignment: .top, spacing: 12) {
            Text("\(planned.number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if planned.stop.isPriority {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(planned.stop.name)
                        .font(.headline)
                }
                Text("Arrive about \(timeText(planned.arrival)), \(Int(planned.stop.serviceMinutes.rounded())) min on site\(planned.stop.isLearned ? "" : " (estimate)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if planned.travelMinutes > 0.5 {
                    if let leg = leg {
                        Text("\(Int(planned.travelMinutes.rounded())) min drive, \((leg.meters / 1609.34).formatted(.number.precision(.fractionLength(1)))) mi by road")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(planned.travelMinutes.rounded())) min drive (straight-line estimate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let deadline = planned.stop.deadline {
                    let spare = Int(deadline.timeIntervalSince(planned.finish) / 60)
                    if spare >= 0 {
                        Text("Due by \(timeText(deadline)), \(spare) min to spare")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    } else {
                        Text("Due by \(timeText(deadline)), late by \(-spare) min")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }
                Button {
                    openDirections(to: planned.stop)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func shareText(_ route: PlannedRoute) -> String {
        var lines = ["\(truckName(route.id)) route"]
        for planned in route.stops {
            var line = "\(planned.number). \(planned.stop.name)"
            if !planned.stop.address.isEmpty && planned.stop.address != planned.stop.name {
                line += " - \(planned.stop.address)"
            }
            line += " (about \(timeText(planned.arrival)))"
            if let deadline = planned.stop.deadline {
                line += " DUE BY \(timeText(deadline))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Opens Apple Maps with turn-by-turn driving directions to the stop.
    private func openDirections(to stop: RouteStop) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Building the route

    private func rebuild() {
        let storm = storms.first { $0.isActive }
        let reference = storm?.startedAt ?? Date()
        let cleaned = inchesText.replacingOccurrences(of: ",", with: ".")
        let inches = Double(cleaned) ?? 3
        let fleetRate = PlowEstimator.fleetMinutesPerInch(properties)

        var stops: [RouteStop] = []
        var learned = 0
        for property in properties {
            guard let lat = property.latitude, let lon = property.longitude else { continue }
            if let storm = storm, property.isDone(in: storm) { continue }

            let estimate = PlowEstimator.estimate(
                for: property,
                inches: inches,
                fleetPerInch: fleetRate,
                defaultMinutes: Double(defaultMinutes)
            )
            if estimate.learned { learned += 1 }

            stops.append(RouteStop(
                id: property.persistentModelID,
                name: property.displayName,
                address: property.address,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                serviceMinutes: estimate.minutes,
                isLearned: estimate.learned,
                isPriority: property.isPriorityFlag,
                deadline: property.deadline(after: reference)
            ))
        }

        let start = fromMyLocation ? locationService.currentCoordinate : nil
        let now = Date()
        let groups = RoutePlanner.cluster(stops, into: trucks)
        var planned: [PlannedRoute] = []
        for (index, group) in groups.enumerated() {
            let ordered = RoutePlanner.plan(
                stops: group,
                start: start,
                startTime: now,
                mph: Double(speedMPH)
            )
            planned.append(PlannedRoute(id: index + 1, stops: ordered))
        }

        startCoordinate = start
        planStart = now
        routes = planned
        learnedCount = learned
        totalCount = stops.count
    }

    // MARK: - Road routes from Apple Maps

    private func loadRoadLegs() async {
        var needed: [(key: LegKey, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D)] = []
        for route in routes {
            var previous: RouteStop?
            for planned in route.stops {
                let key = LegKey(from: previous?.id, to: planned.stop.id)
                var source: CLLocationCoordinate2D?
                if let previous = previous {
                    source = previous.coordinate
                } else {
                    source = startCoordinate
                }
                if let from = source, roadLegs[key] == nil, !failedLegs.contains(key) {
                    needed.append((key: key, from: from, to: planned.stop.coordinate))
                }
                previous = planned.stop
            }
        }

        guard !needed.isEmpty else {
            loadingText = nil
            return
        }

        for (index, item) in needed.enumerated() {
            if Task.isCancelled { return }
            loadingText = "Loading road routes (\(index + 1) of \(needed.count))..."
            await fetchLeg(key: item.key, from: item.from, to: item.to)
            // Apple limits how fast an app can ask for directions, so go slowly.
            try? await Task.sleep(nanoseconds: 1_300_000_000)
        }
        loadingText = nil
    }

    private func fetchLeg(key: LegKey, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        for attempt in 0..<2 {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .automobile

            do {
                let response = try await MKDirections(request: request).calculate()
                if let route = response.routes.first {
                    roadLegs[key] = RoadLeg(
                        coordinates: route.polyline.coordinateList,
                        seconds: route.expectedTravelTime,
                        meters: route.distance
                    )
                } else {
                    failedLegs.insert(key)
                }
                return
            } catch {
                if let mapError = error as? MKError, mapError.code == .loadingThrottled, attempt == 0 {
                    loadingText = "Apple is limiting requests. Waiting 30 seconds..."
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if Task.isCancelled { return }
                    continue
                }
                failedLegs.insert(key)
                return
            }
        }
    }
}
