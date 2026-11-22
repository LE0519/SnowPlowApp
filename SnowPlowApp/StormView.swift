import SwiftUI
import SwiftData

/// The Jobs tab: every property for the current storm, with large Done buttons.
struct StormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @Query private var properties: [Property]
    @AppStorage("driverName") private var driverName = "Driver"

    private var activeStorm: Storm? {
        storms.first { $0.isActive }
    }

    private var pastStorms: [Storm] {
        storms.filter { !$0.isActive }
    }

    private func priorityTodo(_ storm: Storm) -> [Property] {
        properties
            .filter { $0.isPriorityFlag && !$0.isDone(in: storm) }
            .sorted { first, second in
                let a = first.deadline(for: storm) ?? Date.distantFuture
                let b = second.deadline(for: storm) ?? Date.distantFuture
                return a < b
            }
    }

    private func otherProperties(_ storm: Storm) -> [Property] {
        properties
            .filter { !($0.isPriorityFlag && !$0.isDone(in: storm)) }
            .sorted { $0.displayName < $1.displayName }
    }

    private func doneCount(in storm: Storm) -> Int {
        properties.filter { $0.isDone(in: storm) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if let storm = activeStorm {
                    let todo = priorityTodo(storm)
                    if !todo.isEmpty {
                        Section("Priority") {
                            ForEach(todo) { property in
                                PriorityRow(property: property, storm: storm, driverName: driverName)
                            }
                        }
                    }

                    Section("\(doneCount(in: storm)) of \(properties.count) done") {
                        if properties.isEmpty {
                            Text("Add customers and properties first.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(otherProperties(storm)) { property in
                            StormPropertyRow(property: property, storm: storm, driverName: driverName)
                        }
                    }
                } else {
                    Section {
                        Text("No storm is running. Start one from the Home tab.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !pastStorms.isEmpty {
                    Section("Past storms") {
                        ForEach(pastStorms) { storm in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(storm.name)
                                    .font(.headline)
                                Text(summary(for: storm))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: auth.isDriver ? nil : deletePastStorms)
                    }
                }
            }
            .navigationTitle("Jobs")
        }
    }

    private func summary(for storm: Storm) -> String {
        let propertyCount = Set(storm.records.compactMap { $0.property?.persistentModelID }).count
        let visits = storm.records.count
        return "\(propertyCount) properties, \(visits) visits"
    }

    private func deletePastStorms(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(pastStorms[index])
        }
    }
}

struct StormPropertyRow: View {
    @Environment(\.modelContext) private var modelContext
    let property: Property
    let storm: Storm
    let driverName: String

    private var records: [ServiceRecord] {
        storm.records
            .filter { $0.property === property }
            .sorted { $0.completedAt > $1.completedAt }
    }

    private func doneText(_ latest: ServiceRecord, visits: Int) -> String {
        let time = latest.completedAt.formatted(date: .omitted, time: .shortened)
        let how = latest.isAutomatic ? "auto" : "manual"
        var text = "Done \(time) by \(latest.driverName) (\(how))"
        if visits > 1 {
            text += ", \(visits) visits"
        }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(property.displayName)
                    .font(.title3.bold())
                if !property.address.isEmpty && property.displayName != property.address {
                    Text(property.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let latest = records.first {
                    Text(doneText(latest, visits: records.count))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if records.isEmpty {
                Button {
                    markDone()
                } label: {
                    Text("Done")
                        .font(.title3.bold())
                        .frame(minWidth: 72, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 6)
        .swipeActions {
            if !records.isEmpty {
                Button("Again") {
                    markDone()
                }
                .tint(.blue)
                Button("Undo", role: .destructive) {
                    undoLatest()
                }
            }
        }
    }

    private func markDone() {
        JobActions.markDone(property, in: storm, driver: driverName, context: modelContext)
    }

    private func undoLatest() {
        if let latest = records.first {
            modelContext.delete(latest)
            try? modelContext.save()
        }
    }
}
