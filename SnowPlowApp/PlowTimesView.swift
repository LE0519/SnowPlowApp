import SwiftUI
import SwiftData

/// Asks for the storm's snowfall. Used when ending a storm and when fixing an old one.
struct SnowInchesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let actionTitle: String
    let isDestructive: Bool
    let onConfirm: (Double?) -> Void
    @State private var text: String

    init(title: String,
         message: String,
         initial: Double?,
         actionTitle: String,
         isDestructive: Bool = false,
         onConfirm: @escaping (Double?) -> Void) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.isDestructive = isDestructive
        self.onConfirm = onConfirm
        let start: String
        if let initial = initial {
            start = initial == initial.rounded() ? String(Int(initial)) : String(initial)
        } else {
            start = ""
        }
        _text = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Total snowfall in inches (optional)", text: $text)
                        .keyboardType(.decimalPad)
                } footer: {
                    Text("Used to learn how long each property takes per inch of snow. Leave it blank if you don't know.")
                }

                Section {
                    Button(actionTitle, role: isDestructive ? .destructive : nil) {
                        confirm()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func confirm() {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        var value = Double(cleaned)
        if let number = value, number <= 0 {
            value = nil
        }
        onConfirm(value)
        dismiss()
    }
}

/// Shows what the app has learned about how long each property takes.
struct PlowTimesView: View {
    @Query private var properties: [Property]

    private let stormsNeeded = 3

    private struct Sample {
        let minutes: Double
        let inches: Double?
        let stormID: PersistentIdentifier?
    }

    /// Only visits with both an arrival and a departure time count. Very short and very long
    /// visits are ignored, since they are usually GPS glitches or a stop for something else.
    private func samples(for property: Property) -> [Sample] {
        property.records.compactMap { record in
            guard let arrived = record.arrivedAt, let departed = record.departedAt else { return nil }
            let minutes = departed.timeIntervalSince(arrived) / 60
            guard minutes >= 1, minutes <= 180 else { return nil }
            return Sample(
                minutes: minutes,
                inches: record.storm?.snowInches,
                stormID: record.storm?.persistentModelID
            )
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    private var allSamples: [Sample] {
        properties.flatMap { samples(for: $0) }
    }

    private var stormsWithData: Int {
        let ids = allSamples
            .filter { ($0.inches ?? 0) > 0 }
            .compactMap { $0.stormID }
        return Set(ids).count
    }

    private var sortedProperties: [Property] {
        properties.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning phase")
                        .font(.headline)
                    ProgressView(value: Double(min(stormsWithData, stormsNeeded)), total: Double(stormsNeeded))
                    Text("\(stormsWithData) of \(stormsNeeded) storms with plow times and snowfall recorded.")
                        .font(.subheadline)
                    Text("\(allSamples.count) timed visits so far.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("A visit is timed from when the phone enters a property's circle until it leaves. Only automatic check-offs are timed. Enter the snowfall when you end each storm. After about \(stormsNeeded) storms there is enough to start suggesting routes.")
            }

            Section("By property") {
                if properties.isEmpty {
                    Text("No properties yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedProperties) { property in
                    row(for: property)
                }
            }
        }
        .navigationTitle("Plow times")
    }

    @ViewBuilder
    private func row(for property: Property) -> some View {
        let list = samples(for: property)
        VStack(alignment: .leading, spacing: 3) {
            Text(property.displayName)
                .font(.headline)
            if let typical = median(list.map { $0.minutes }) {
                Text("\(list.count) timed \(list.count == 1 ? "visit" : "visits"), typically \(Int(typical.rounded())) min")
                    .font(.subheadline)
                let perInch = list.compactMap { sample -> Double? in
                    guard let inches = sample.inches, inches >= 0.5 else { return nil }
                    return sample.minutes / inches
                }
                if let value = median(perInch) {
                    Text("About \(value.formatted(.number.precision(.fractionLength(1)))) min per inch of snow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No timed visits yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
