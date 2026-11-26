import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(AuthService.self) private var auth
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @Query private var properties: [Property]
    @AppStorage("driverName") private var driverName = "Driver"
    @AppStorage("dwellMinutes") private var dwellMinutes = 3
    @State private var showEndSheet = false

    private var activeStorm: Storm? {
        storms.first { $0.isActive }
    }

    private var lastFinishedStorm: Storm? {
        storms.first { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let storm = activeStorm {
                        stormCard(storm)
                        statusCard(storm)
                        priorityCard(storm)
                        toolsSection
                        endStormButton
                        gpsFootnote
                    } else {
                        idleCard
                        lastStormCard
                        toolsSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .sheet(isPresented: $showEndSheet) {
                SnowInchesSheet(
                    title: "End this storm?",
                    message: "GPS watching will stop for this storm. Everyone still clocked in is clocked out.",
                    initial: nil,
                    actionTitle: "End Storm",
                    isDestructive: true
                ) { inches in
                    endStorm(inches: inches)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func toolTile(_ title: String, _ systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.blue)
            Text(title)
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.primary)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                NavigationLink {
                    RouteView()
                } label: {
                    toolTile("Route planner", "point.topleft.down.curvedto.point.bottomright.up")
                }
                NavigationLink {
                    HoursView()
                } label: {
                    toolTile(auth.isDriver ? "My hours" : "Plow hours", "clock")
                }
                if !auth.isDriver {
                    NavigationLink {
                        PlowTimesView()
                    } label: {
                        toolTile("Plow times", "chart.bar")
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - No storm running

    private var idleCard: some View {
        card {
            VStack(spacing: 14) {
                Image(systemName: "snowflake")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                Text("No storm running")
                    .font(.title2.bold())
                Text("Tap Start Storm when you begin plowing. You'll be clocked in and GPS will start watching for arrivals.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    startStorm()
                } label: {
                    Text("Start Storm")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var lastStormCard: some View {
        if let last = lastFinishedStorm {
            NavigationLink {
                StormDetailView(storm: last)
            } label: {
                card {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last storm")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(last.name)
                                .font(.headline)
                            Text(summary(for: last))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func summary(for storm: Storm) -> String {
        let done = Set(storm.records.filter { $0.isFinished }.compactMap { $0.property?.persistentModelID }).count
        return "\(done) of \(properties.count) properties done"
    }

    // MARK: - Storm running

    private func priorityTodo(_ storm: Storm) -> [Property] {
        properties
            .filter { $0.isPriorityFlag && !$0.isDone(in: storm) }
            .sorted { first, second in
                let a = first.deadline(for: storm) ?? Date.distantFuture
                let b = second.deadline(for: storm) ?? Date.distantFuture
                return a < b
            }
    }

    private func myOpenShift(_ storm: Storm) -> Shift? {
        storm.shifts.first { $0.endedAt == nil && $0.driverUID == auth.userID }
    }

    private func stormCard(_ storm: Storm) -> some View {
        let done = properties.filter { $0.isDone(in: storm) }.count
        let working = properties.filter { $0.isInProgress(in: storm) }.count
        return card {
            VStack(spacing: 8) {
                Text("STORM IN PROGRESS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(storm.startedAt, style: .timer)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(value: Double(done), total: Double(max(properties.count, 1)))
                Text("\(done) of \(properties.count) properties done")
                    .font(.headline)
                if working > 0 {
                    Text("\(working) in progress")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var atPropertyView: some View {
        if let name = locationService.arrivedName, let since = locationService.arrivedAt {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("At \(name)")
                        .font(.title3.bold())
                    Text(locationService.arrivedIsDone
                         ? "Already marked done"
                         : (locationService.arrivedInProgress
                            ? "In progress. Marked done when you leave."
                            : "Marked in progress at \(dwellMinutes):00"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(since, style: .timer)
                    .font(.title.monospacedDigit().bold())
            }
            .padding(12)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Text("Not at a saved property. GPS is watching for arrivals.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusCard(_ storm: Storm) -> some View {
        if let shift = myOpenShift(storm) {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("You're clocked in", systemImage: "clock.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Spacer()
                        Text(shift.startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                    }

                    atPropertyView

                    if !locationService.isTracking {
                        Button {
                            locationService.start()
                        } label: {
                            Label("GPS is off. Tap to turn it on", systemImage: "location.slash")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    Button {
                        clockOut(shift)
                    } label: {
                        Label("Clock Out", systemImage: "clock")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else {
            card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("You're not clocked in")
                        .font(.headline)
                    Text("Clock in to start your hours and turn on GPS for this phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        clockIn(to: storm)
                    } label: {
                        Label("Clock In", systemImage: "clock.fill")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private func priorityCard(_ storm: Storm) -> some View {
        let todo = priorityTodo(storm)
        if !todo.isEmpty {
            let shown = Array(todo.prefix(3))
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Priority", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(shown) { property in
                        PriorityRow(property: property, storm: storm, driverName: driverName)
                        if property.persistentModelID != shown.last?.persistentModelID {
                            Divider()
                        }
                    }
                    if todo.count > shown.count {
                        Text("\(todo.count - shown.count) more on the Jobs tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var endStormButton: some View {
        Button(role: .destructive) {
            showEndSheet = true
        } label: {
            Label("End Storm", systemImage: "stop.circle")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
    }

    private var gpsFootnote: some View {
        VStack(spacing: 6) {
            Text(locationService.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if locationService.isDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func startStorm() {
        let name = "Storm " + Date().formatted(date: .abbreviated, time: .omitted)
        let storm = Storm(name: name)
        modelContext.insert(storm)
        // Starting a storm also clocks you in.
        clockIn(to: storm)
    }

    private func clockIn(to storm: Storm) {
        let shift = Shift(driverName: driverName, driverUID: auth.userID)
        modelContext.insert(shift)
        shift.storm = storm
        try? modelContext.save()
        locationService.start()
    }

    private func clockOut(_ shift: Shift) {
        shift.endedAt = Date()
        try? modelContext.save()
        locationService.stop()
    }

    private func endStorm(inches: Double?) {
        if let storm = activeStorm {
            let now = Date()
            storm.endedAt = now
            storm.snowInches = inches
            for record in storm.records where record.inProgress == true {
                record.inProgress = false
                record.departedAt = now
                record.completedAt = now
            }
            // The owner clocks everyone out. A driver clocks out only themselves,
            // and the others are clocked out when they sync.
            for shift in storm.shifts where shift.endedAt == nil {
                if !auth.isDriver || shift.driverUID == auth.userID {
                    shift.endedAt = now
                }
            }
            try? modelContext.save()
        }
        locationService.stop()
    }
}
