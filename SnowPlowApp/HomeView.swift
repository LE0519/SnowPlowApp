import SwiftUI
import SwiftData
import UIKit

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(AuthService.self) private var auth
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @Query private var properties: [Property]
    @Query private var customers: [Customer]
    @AppStorage("driverName") private var driverName = "Driver"
    @AppStorage("dwellMinutes") private var dwellMinutes = 3
    @State private var confirmEnd = false

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
                        activeContent(storm)
                    } else {
                        idleContent
                    }
                }
                .padding()
            }
            .navigationTitle("Home")
            .alert("End this storm?", isPresented: $confirmEnd) {
                Button("End storm", role: .destructive) {
                    endStorm()
                }
                Button("Keep going", role: .cancel) { }
            } message: {
                Text("GPS watching will stop for this storm.")
            }
        }
    }

    // MARK: - No storm running

    @ViewBuilder
    private var idleContent: some View {
        Button {
            startStorm()
        } label: {
            Label("Start Storm", systemImage: "snowflake")
                .font(.title.bold())
                .frame(maxWidth: .infinity, minHeight: 90)
        }
        .buttonStyle(.borderedProminent)

        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            Text("\(customers.count) customers, \(properties.count) properties")
                .foregroundStyle(.secondary)
            if let last = lastFinishedStorm {
                let doneCount = Set(last.records.compactMap { $0.property?.persistentModelID }).count
                Text("Last storm: \(last.name), \(doneCount) properties done")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

        hoursLink
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

    private func doneCount(in storm: Storm) -> Int {
        properties.filter { $0.isDone(in: storm) }.count
    }

    @ViewBuilder
    private func activeContent(_ storm: Storm) -> some View {
        VStack(spacing: 6) {
            Text("STORM TIME")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(storm.startedAt, style: .timer)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(storm.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

        VStack(alignment: .leading, spacing: 8) {
            let done = doneCount(in: storm)
            Text("\(done) of \(properties.count) properties done")
                .font(.title3.bold())
            ProgressView(value: Double(done), total: Double(max(properties.count, 1)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

        if let name = locationService.arrivedName, let since = locationService.arrivedAt {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("At \(name)")
                        .font(.headline)
                    Text(locationService.arrivedIsDone
                         ? "Already marked done"
                         : "Checks off automatically at \(dwellMinutes):00")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(since, style: .timer)
                    .font(.title2.monospacedDigit().bold())
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }

        let todo = priorityTodo(storm)
        if !todo.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Priority")
                    .font(.headline)
                ForEach(Array(todo.prefix(5))) { property in
                    PriorityRow(property: property, storm: storm, driverName: driverName)
                    if property.persistentModelID != todo.prefix(5).last?.persistentModelID {
                        Divider()
                    }
                }
                if todo.count > 5 {
                    Text("+ \(todo.count - 5) more on the Jobs tab")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }

        VStack(alignment: .leading, spacing: 6) {
            Text(locationService.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if locationService.isDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)

        if let shift = myOpenShift(storm) {
            VStack(spacing: 10) {
                HStack {
                    Label("Clocked in", systemImage: "clock.fill")
                        .font(.headline)
                    Spacer()
                    Text(shift.startedAt, style: .timer)
                        .font(.title2.monospacedDigit().bold())
                }
                if !locationService.isTracking {
                    Button {
                        locationService.start()
                    } label: {
                        Label("GPS is off. Tap to restart it", systemImage: "location.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    clockOut(shift)
                } label: {
                    Label("Clock Out", systemImage: "clock")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else {
            Button {
                clockIn(to: storm)
            } label: {
                Label("Clock In", systemImage: "clock.fill")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
        }

        hoursLink

        Button(role: .destructive) {
            confirmEnd = true
        } label: {
            Label("End Storm", systemImage: "stop.circle.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
    }

    private var hoursLink: some View {
        NavigationLink {
            HoursView()
        } label: {
            HStack {
                Label(auth.isDriver ? "My hours" : "Plow hours", systemImage: "clock")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func myOpenShift(_ storm: Storm) -> Shift? {
        storm.shifts.first { $0.endedAt == nil && $0.driverUID == auth.userID }
    }

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

    private func endStorm() {
        if let storm = activeStorm {
            let now = Date()
            storm.endedAt = now
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
