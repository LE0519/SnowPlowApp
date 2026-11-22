import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct RouteView: View {
    @Environment(LocationService.self) private var locationService
    @Query private var properties: [Property]
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @AppStorage("routeDefaultMinutes") private var defaultMinutes = 10
    @AppStorage("routeSpeedMPH") private var speedMPH = 20

    @State private var inchesText = ""
    @State private var trucks = 1
    @State private var fromMyLocation = true
    @State private var routes: [PlannedRoute] = []
    @State private var learnedCount = 0
    @State private var totalCount = 0

    private var rebuildKey: String {
        "\(inchesText)|\(trucks)|\(fromMyLocation)|\(properties.count)|\(defaultMinutes)|\(speedMPH)"
    }

    private var lateTotal: Int {
        routes.reduce(0) { $0 + $1.lateCount }
    }

    private func color(for routeID: Int) -> Color {
        let palette: [Color] = [.blue, .green, .purple, .red]
        return palette[(routeID - 1) % palette.count]
    }

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
                Section {
                    if lateTotal == 0 {
                        Label("Every priority deadline looks reachable.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("\(lateTotal) priority \(lateTotal == 1 ? "stop" : "stops") would likely be late. Try another truck, or move the deadline.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    mapView
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                }

                ForEach(routes) { route in
                    Section {
                        ForEach(route.stops) { planned in
                            stopRow(planned, tint: color(for: route.id))
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
    }

    private var planFooter: String {
        var text = "Uses your own recorded times for \(learnedCount) of \(totalCount) properties"
        if totalCount > learnedCount {
            text += " and a guess of \(defaultMinutes) minutes for the rest (change this in Settings)"
        }
        text += ". Drive times are straight-line distances, not roads, so treat the times as estimates."
        return text
    }

    // MARK: - Pieces

    private var mapView: some View {
        Map {
            ForEach(routes) { route in
                if route.stops.count > 1 {
                    MapPolyline(coordinates: route.stops.map { $0.stop.coordinate })
                        .stroke(color(for: route.id), lineWidth: 3)
                }
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
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func routeHeader(_ route: PlannedRoute) -> some View {
        let finishText = route.finish.map { timeText($0) } ?? "-"
        let hours = Int((route.serviceMinutes + route.travelMinutes) / 60)
        let minutes = Int(route.serviceMinutes + route.travelMinutes) % 60
        VStack(alignment: .leading, spacing: 2) {
            Text("Truck \(route.id): \(route.stops.count) stops")
                .font(.headline)
                .foregroundStyle(color(for: route.id))
            Text("About \(hours) h \(minutes) m of work, done around \(finishText)")
                .font(.caption)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func stopRow(_ planned: PlannedStop, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(planned.number)")
                .font(.headline)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.2)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if planned.stop.isPriority {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                    }
                    Text(planned.stop.name)
                        .font(.headline)
                }
                let minutes = Int(planned.stop.serviceMinutes.rounded())
                Text("Arrive about \(timeText(planned.arrival)), \(minutes) min\(planned.stop.isLearned ? "" : " (estimate)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        .padding(.vertical, 2)
    }

    private func shareText(_ route: PlannedRoute) -> String {
        var lines = ["Truck \(route.id) route"]
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
        let groups = RoutePlanner.cluster(stops, into: trucks)
        var planned: [PlannedRoute] = []
        for (index, group) in groups.enumerated() {
            let ordered = RoutePlanner.plan(
                stops: group,
                start: start,
                startTime: Date(),
                mph: Double(speedMPH)
            )
            planned.append(PlannedRoute(id: index + 1, stops: ordered))
        }

        routes = planned
        learnedCount = learned
        totalCount = stops.count
    }
}
