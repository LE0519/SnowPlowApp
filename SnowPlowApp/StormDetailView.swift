import SwiftUI
import SwiftData

/// Everything about one storm: who worked how long, how much got done, and what was missed.
struct StormDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var properties: [Property]
    let storm: Storm
    @State private var editingSnow = false

    // MARK: - Numbers

    private var endDate: Date {
        storm.endedAt ?? Date()
    }

    private var stormSeconds: TimeInterval {
        max(0, endDate.timeIntervalSince(storm.startedAt))
    }

    private var recordsByTime: [ServiceRecord] {
        storm.records.sorted { $0.completedAt < $1.completedAt }
    }

    private var doneIDs: Set<PersistentIdentifier> {
        Set(storm.records.compactMap { $0.property?.persistentModelID })
    }

    private var doneCount: Int {
        properties.filter { doneIDs.contains($0.persistentModelID) }.count
    }

    private var percentDone: Int {
        let total = max(properties.count, 1)
        return Int((Double(doneCount) / Double(total) * 100).rounded())
    }

    private var notDone: [Property] {
        properties
            .filter { !doneIDs.contains($0.persistentModelID) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var autoCount: Int {
        storm.records.filter { $0.isAutomatic }.count
    }

    private var manualCount: Int {
        storm.records.count - autoCount
    }

    private struct CrewRow: Identifiable {
        let id: String
        let name: String
        let seconds: TimeInterval
        let jobs: Int
    }

    private var crew: [CrewRow] {
        var names = Set<String>()
        for shift in storm.shifts { names.insert(shift.driverName) }
        for record in storm.records { names.insert(record.driverName) }

        return names.sorted().map { name in
            var seconds = 0.0
            for shift in storm.shifts where shift.driverName == name {
                let end = shift.endedAt ?? storm.endedAt ?? Date()
                seconds += max(0, end.timeIntervalSince(shift.startedAt))
            }
            let jobs = storm.records.filter { $0.driverName == name }.count
            return CrewRow(id: name, name: name, seconds: seconds, jobs: jobs)
        }
    }

    private var totalCrewSeconds: TimeInterval {
        crew.reduce(0) { $0 + $1.seconds }
    }

    private struct PriorityResult: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let due: Date
        let doneAt: Date?

        var onTime: Bool {
            if let doneAt = doneAt {
                return doneAt <= due
            }
            return false
        }
    }

    private var priorityResults: [PriorityResult] {
        properties.compactMap { property in
            guard let due = property.deadline(for: storm) else { return nil }
            let doneAt = storm.records
                .filter { $0.property === property }
                .map { $0.completedAt }
                .min()
            return PriorityResult(id: property.persistentModelID, name: property.displayName, due: due, doneAt: doneAt)
        }
        .sorted { $0.due < $1.due }
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func jobsPerHour(jobs: Int, seconds: TimeInterval) -> String? {
        guard seconds >= 600 else { return nil }
        let value = Double(jobs) / (seconds / 3600)
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    private func crewDetail(_ person: CrewRow) -> String {
        var text = "\(person.jobs) \(person.jobs == 1 ? "job" : "jobs")"
        if let rate = jobsPerHour(jobs: person.jobs, seconds: person.seconds) {
            text += ", \(rate) per hour"
        }
        return text
    }

    private func recordDetail(_ record: ServiceRecord) -> String {
        let how = record.isAutomatic ? "auto" : "manual"
        var text = "\(timeText(record.completedAt)) by \(record.driverName) (\(how))"
        if let arrived = record.arrivedAt, let departed = record.departedAt {
            let minutes = Int(departed.timeIntervalSince(arrived) / 60)
            if minutes >= 1 {
                text += ", about \(minutes) min on site"
            }
        }
        return text
    }

    private var snowText: String {
        if let inches = storm.snowInches {
            return "\(inches.formatted()) in"
        }
        return "Not recorded"
    }

    // MARK: - Screen

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Started", value: storm.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let ended = storm.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Status", value: "In progress")
                }
                LabeledContent("Length", value: HoursFormat.text(stormSeconds))
                Button {
                    editingSnow = true
                } label: {
                    HStack {
                        Text("Snowfall")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(snowText)
                            .foregroundStyle(.secondary)
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                }
            }

            Section("Completion") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(percentDone)% of properties done")
                        .font(.title2.bold())
                    ProgressView(value: Double(doneCount), total: Double(max(properties.count, 1)))
                    Text("\(doneCount) of \(properties.count) properties, \(storm.records.count) visits")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                LabeledContent("Automatic check-offs", value: "\(autoCount)")
                LabeledContent("Manual check-offs", value: "\(manualCount)")
                if let first = recordsByTime.first, let last = recordsByTime.last {
                    LabeledContent("First job done", value: timeText(first.completedAt))
                    LabeledContent("Last job done", value: timeText(last.completedAt))
                }
            }

            if !crew.isEmpty {
                Section {
                    ForEach(crew) { person in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(person.name.isEmpty ? "(unknown)" : person.name)
                                    .font(.headline)
                                Text(crewDetail(person))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(HoursFormat.text(person.seconds))
                                .font(.headline.monospacedDigit())
                        }
                    }
                    LabeledContent("Total crew hours", value: HoursFormat.text(totalCrewSeconds))
                        .font(.headline)
                } header: {
                    Text("Crew")
                } footer: {
                    Text("Hours come from Clock In and Clock Out. Jobs per hour is jobs checked off divided by hours worked.")
                }
            }

            if !priorityResults.isEmpty {
                Section {
                    ForEach(priorityResults) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.headline)
                                Text(result.doneAt == nil
                                     ? "Due by \(timeText(result.due)), not done"
                                     : "Due by \(timeText(result.due)), done \(timeText(result.doneAt ?? result.due))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: result.onTime ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.onTime ? Color.green : Color.red)
                        }
                    }
                } header: {
                    let onTime = priorityResults.filter { $0.onTime }.count
                    Text("Priority deadlines: \(onTime) of \(priorityResults.count) on time")
                }
            }

            Section("Completed jobs (\(recordsByTime.count))") {
                if recordsByTime.isEmpty {
                    Text("No jobs were checked off.")
                        .foregroundStyle(.secondary)
                }
                ForEach(recordsByTime) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.property?.displayName ?? "Deleted property")
                            .font(.headline)
                        Text(recordDetail(record))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !notDone.isEmpty {
                Section("Not done (\(notDone.count))") {
                    ForEach(notDone) { property in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(property.displayName)
                                .font(.headline)
                            if !property.address.isEmpty && property.displayName != property.address {
                                Text(property.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(storm.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editingSnow) {
            SnowInchesSheet(
                title: "Snowfall",
                message: storm.name,
                initial: storm.snowInches,
                actionTitle: "Save"
            ) { inches in
                storm.snowInches = inches
                try? modelContext.save()
            }
        }
    }
}
