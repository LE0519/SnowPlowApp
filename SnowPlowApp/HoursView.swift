import SwiftUI
import SwiftData

enum HoursPeriod: String, CaseIterable, Identifiable {
    case latestStorm = "Latest storm"
    case week = "Last 7 days"
    case month = "Last 30 days"
    case all = "All time"

    var id: String { rawValue }
}

enum HoursFormat {
    static func seconds(_ shift: Shift, now: Date) -> TimeInterval {
        max(0, (shift.endedAt ?? now).timeIntervalSince(shift.startedAt))
    }

    static func text(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes / 60) h \(minutes % 60) m"
    }
}

private struct DriverTotal: Identifiable {
    let id: String
    let name: String
    let shifts: [Shift]

    func seconds(now: Date) -> TimeInterval {
        shifts.reduce(0) { $0 + HoursFormat.seconds($1, now: now) }
    }
}

struct HoursView: View {
    @Environment(AuthService.self) private var auth
    @Query(sort: \Shift.startedAt, order: .reverse) private var allShifts: [Shift]
    @Query(sort: \Storm.startedAt, order: .reverse) private var storms: [Storm]
    @State private var period: HoursPeriod = .latestStorm
    @State private var now = Date()
    @State private var exportURL: URL?

    private var visibleShifts: [Shift] {
        var list = allShifts
        if auth.isDriver {
            list = list.filter { $0.driverUID == auth.userID }
        }
        switch period {
        case .latestStorm:
            guard let storm = storms.first else { return [] }
            return list.filter { $0.storm === storm }
        case .week:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            return list.filter { $0.startedAt >= cutoff }
        case .month:
            let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
            return list.filter { $0.startedAt >= cutoff }
        case .all:
            return list
        }
    }

    private var totals: [DriverTotal] {
        var groups: [String: [Shift]] = [:]
        for shift in visibleShifts {
            groups[shift.driverUID ?? shift.driverName, default: []].append(shift)
        }
        return groups.map { key, shifts in
            DriverTotal(
                id: key,
                name: shifts.first?.driverName ?? key,
                shifts: shifts.sorted { $0.startedAt > $1.startedAt }
            )
        }
        .sorted { $0.name < $1.name }
    }

    private var grandTotal: TimeInterval {
        visibleShifts.reduce(0) { $0 + HoursFormat.seconds($1, now: now) }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(HoursPeriod.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            if totals.isEmpty {
                Section {
                    Text("No hours recorded for this period yet. Hours count from Clock In to Clock Out.")
                        .foregroundStyle(.secondary)
                }
            } else {
                if !auth.isDriver {
                    Section {
                        LabeledContent("Everyone combined", value: HoursFormat.text(grandTotal))
                            .font(.headline)
                    }
                }
                ForEach(totals) { driver in
                    Section {
                        ForEach(driver.shifts) { shift in
                            shiftRow(shift)
                        }
                    } header: {
                        HStack {
                            Text(driver.name)
                            Spacer()
                            Text(HoursFormat.text(driver.seconds(now: now)))
                        }
                    }
                }
            }
        }
        .navigationTitle(auth.isDriver ? "My hours" : "Plow hours")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear { prepareExport() }
        .onChange(of: period) { _, _ in prepareExport() }
        .onChange(of: allShifts.count) { _, _ in prepareExport() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }

    @ViewBuilder
    private func shiftRow(_ shift: Shift) -> some View {
        let content = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(shift.storm?.name ?? "Storm")
                    .font(.subheadline.bold())
                Text(timeRange(shift))
                    .font(.caption)
                    .foregroundStyle(shift.endedAt == nil ? Color.green : Color.secondary)
            }
            Spacer()
            Text(HoursFormat.text(HoursFormat.seconds(shift, now: now)))
                .monospacedDigit()
        }
        if auth.isDriver {
            content
        } else {
            NavigationLink {
                ShiftEditView(shift: shift)
            } label: {
                content
            }
        }
    }

    private func timeRange(_ shift: Shift) -> String {
        let start = shift.startedAt.formatted(date: .abbreviated, time: .shortened)
        guard let end = shift.endedAt else {
            return "\(start) to now (clocked in)"
        }
        let sameDay = Calendar.current.isDate(shift.startedAt, inSameDayAs: end)
        let endText = sameDay
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
        return "\(start) to \(endText)"
    }

    // MARK: - Export to a spreadsheet file

    private func prepareExport() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        var lines = ["Driver,Storm,Clock in,Clock out,Hours"]
        let current = Date()
        for shift in visibleShifts.sorted(by: { $0.startedAt < $1.startedAt }) {
            let hours = HoursFormat.seconds(shift, now: current) / 3600
            let out = shift.endedAt.map { formatter.string(from: $0) } ?? "still clocked in"
            lines.append([
                quoted(shift.driverName),
                quoted(shift.storm?.name ?? ""),
                quoted(formatter.string(from: shift.startedAt)),
                quoted(out),
                String(format: "%.2f", hours)
            ].joined(separator: ","))
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SnowPlow-hours.csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}

/// Lets the owner fix a shift, for example when someone forgot to clock out.
struct ShiftEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let shift: Shift
    @State private var start: Date
    @State private var end: Date
    @State private var stillOn: Bool
    @State private var confirmDelete = false

    init(shift: Shift) {
        self.shift = shift
        _start = State(initialValue: shift.startedAt)
        _end = State(initialValue: shift.endedAt ?? Date())
        _stillOn = State(initialValue: shift.endedAt == nil)
    }

    var body: some View {
        Form {
            Section("Driver") {
                Text(shift.driverName)
                if let storm = shift.storm {
                    Text(storm.name)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Times") {
                DatePicker("Clock in", selection: $start)
                Toggle("Still clocked in", isOn: $stillOn)
                if !stillOn {
                    DatePicker("Clock out", selection: $end, in: start...)
                }
            }

            Section {
                Button("Delete this shift", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle("Edit shift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
        .alert("Delete this shift?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                modelContext.delete(shift)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Its hours will be removed from the totals.")
        }
    }

    private func save() {
        shift.startedAt = start
        shift.endedAt = stillOn ? nil : max(end, start)
        try? modelContext.save()
        dismiss()
    }
}
