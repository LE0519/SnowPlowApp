import SwiftUI
import SwiftData

extension Property {
    var isPriorityFlag: Bool {
        isPriority ?? false
    }

    /// The customer's name, or the address when there is no name.
    var displayName: String {
        let name = customer?.name ?? ""
        if !name.isEmpty {
            return name
        }
        return address.isEmpty ? "(No name)" : address
    }

    /// The next time this property's "done by" time comes around after the storm began.
    /// A storm that starts at 10 PM with a 7:00 AM deadline means 7:00 AM the next morning.
    func deadline(for storm: Storm) -> Date? {
        deadline(after: storm.startedAt)
    }

    /// The next time this property's "done by" time comes around after the given moment.
    func deadline(after date: Date) -> Date? {
        guard isPriorityFlag, let minutes = deadlineMinutes else { return nil }
        var parts = DateComponents()
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return Calendar.current.nextDate(
            after: date,
            matching: parts,
            matchingPolicy: .nextTime
        )
    }

    func isDone(in storm: Storm) -> Bool {
        storm.records.contains { $0.property === self && $0.isFinished }
    }

    func isInProgress(in storm: Storm) -> Bool {
        storm.records.contains { $0.property === self && !$0.isFinished }
    }
}

enum JobActions {
    static func markDone(_ property: Property, in storm: Storm, driver: String, context: ModelContext) {
        // If an automatic visit is still in progress here, finishing it is the same as marking it done.
        if let open = storm.records.first(where: { $0.property === property && !$0.isFinished }) {
            let now = Date()
            open.inProgress = false
            open.completedAt = now
            open.departedAt = now
            try? context.save()
            return
        }
        let record = ServiceRecord(driverName: driver, isAutomatic: false)
        context.insert(record)
        record.property = property
        record.storm = storm
        try? context.save()
    }
}

/// Switches for marking a property as priority, with an optional "must be done by" time.
struct PriorityEditor: View {
    @Binding var isPriority: Bool
    @Binding var deadlineMinutes: Int?

    private var priorityBinding: Binding<Bool> {
        Binding(
            get: { isPriority },
            set: { newValue in
                isPriority = newValue
                if !newValue {
                    deadlineMinutes = nil
                }
            }
        )
    }

    private var hasDeadline: Binding<Bool> {
        Binding(
            get: { deadlineMinutes != nil },
            set: { on in
                deadlineMinutes = on ? (deadlineMinutes ?? 7 * 60) : nil
            }
        )
    }

    private var deadlineDate: Binding<Date> {
        Binding(
            get: {
                let minutes = deadlineMinutes ?? 7 * 60
                return Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                deadlineMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        Toggle("Priority (school, clinic, etc.)", isOn: priorityBinding)
        if isPriority {
            Toggle("Must be done by a time", isOn: hasDeadline)
            if deadlineMinutes != nil {
                DatePicker("Done by", selection: deadlineDate, displayedComponents: .hourAndMinute)
            }
        }
    }
}

/// A large row for a priority property that is not done yet.
struct PriorityRow: View {
    @Environment(\.modelContext) private var modelContext
    let property: Property
    let storm: Storm
    let driverName: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                    Text(property.displayName)
                        .font(.title3.bold())
                }
                if !property.address.isEmpty && property.displayName != property.address {
                    Text(property.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if property.isInProgress(in: storm) {
                    Text("In progress")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                }
                if let deadline = property.deadline(for: storm) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        let late = timeline.date > deadline
                        let timeText = deadline.formatted(date: .omitted, time: .shortened)
                        Text(late ? "Past due (was due \(timeText))" : "Due by \(timeText)")
                            .font(.subheadline.bold())
                            .foregroundStyle(late ? Color.red : Color.orange)
                    }
                }
            }
            Spacer()
            Button {
                JobActions.markDone(property, in: storm, driver: driverName, context: modelContext)
            } label: {
                Text("Done")
                    .font(.title3.bold())
                    .frame(minWidth: 72, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}
