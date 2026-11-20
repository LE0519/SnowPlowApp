import SwiftUI
import SwiftData
import UIKit

struct StormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @Query private var properties: [Property]
    @AppStorage("driverName") private var driverName = "Driver"

    private var activeStorm: Storm? {
        storms.first { $0.isActive }
    }

    private var pastStorms: [Storm] {
        storms.filter { !$0.isActive }
    }

    private var sortedProperties: [Property] {
        properties.sorted {
            ($0.customer?.name ?? "") < ($1.customer?.name ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let storm = activeStorm {
                    activeSection(storm)
                } else {
                    Section {
                        Button {
                            startStorm()
                        } label: {
                            Label("Start a storm", systemImage: "snowflake")
                                .font(.headline)
                        }
                    } footer: {
                        Text("Start a storm when you begin plowing. GPS watching and completed properties are tracked for each storm.")
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
                        .onDelete(perform: deletePastStorms)
                    }
                }
            }
            .navigationTitle("Storm")
        }
    }

    @ViewBuilder
    private func activeSection(_ storm: Storm) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(storm.name)
                    .font(.headline)
                Text("Started \(storm.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(doneCount(in: storm)) of \(properties.count) properties done")
                    .font(.subheadline)
            }
            Button(role: .destructive) {
                endStorm(storm)
            } label: {
                Label("End storm", systemImage: "stop.circle")
            }
        }

        Section("GPS") {
            Text(locationService.statusText)
                .font(.subheadline)
            if locationService.isDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }

        Section("Properties") {
            if properties.isEmpty {
                Text("Add customers and properties first.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sortedProperties) { property in
                StormPropertyRow(property: property, storm: storm, driverName: driverName)
            }
        }
    }

    private func doneCount(in storm: Storm) -> Int {
        properties.filter { property in
            storm.records.contains { $0.property === property }
        }.count
    }

    private func summary(for storm: Storm) -> String {
        let propertyCount = Set(storm.records.compactMap { $0.property?.persistentModelID }).count
        let visits = storm.records.count
        return "\(propertyCount) properties, \(visits) visits"
    }

    private func startStorm() {
        let name = "Storm " + Date().formatted(date: .abbreviated, time: .omitted)
        modelContext.insert(Storm(name: name))
        try? modelContext.save()
        locationService.start()
    }

    private func endStorm(_ storm: Storm) {
        storm.endedAt = Date()
        try? modelContext.save()
        locationService.stop()
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

    private var title: String {
        let name = property.customer?.name ?? ""
        return name.isEmpty ? "(No name)" : name
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(property.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let latest = records.first {
                    Text(doneText(latest, visits: records.count))
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Spacer()
            if records.isEmpty {
                Button("Done") {
                    markDone()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
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
        let record = ServiceRecord(driverName: driverName, isAutomatic: false)
        modelContext.insert(record)
        record.property = property
        record.storm = storm
        try? modelContext.save()
    }

    private func undoLatest() {
        if let latest = records.first {
            modelContext.delete(latest)
            try? modelContext.save()
        }
    }
}
    }
}
