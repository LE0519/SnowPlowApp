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

    private var stormsWithData: Int {
        var ids: [PersistentIdentifier] = []
        for property in properties {
            for record in property.records {
                if record.arrivedAt != nil, record.departedAt != nil,
                   (record.storm?.snowInches ?? 0) > 0,
                   let id = record.storm?.persistentModelID {
                    ids.append(id)
                }
            }
        }
        return Set(ids).count
    }

    private var timedVisits: Int {
        properties.reduce(0) { $0 + PlowEstimator.samples(for: $1).count }
    }

    private var sortedProperties: [Property] {
        properties.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        let model = PlowEstimator.buildModel(properties: properties)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning phase")
                        .font(.headline)
                    ProgressView(value: Double(min(stormsWithData, stormsNeeded)), total: Double(stormsNeeded))
                    Text("\(stormsWithData) of \(stormsNeeded) storms with plow times and snowfall recorded.")
                        .font(.subheadline)
                    Text("\(timedVisits) timed visits so far.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("A visit is timed from when the phone enters a property's circle until it leaves. Only automatic visits are timed. Enter the snowfall when you end each storm.")
            }

            Section {
                Text(model.curve.summary)
                    .font(.subheadline)
            } header: {
                Text("Storm size")
            } footer: {
                Text("You can change the light-snow limit and the extra time per inch in Settings, under Route planning.")
            }

            Section("By property") {
                if properties.isEmpty {
                    Text("No properties yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedProperties) { property in
                    row(for: property, model: model)
                }
            }
        }
        .navigationTitle("Plow times")
    }

    @ViewBuilder
    private func row(for property: Property, model: PlowModel) -> some View {
        let count = PlowEstimator.samples(for: property).count
        VStack(alignment: .leading, spacing: 3) {
            Text(property.displayName)
                .font(.headline)
            if let base = model.lightSnowMinutes(for: property) {
                Text("\(count) timed \(count == 1 ? "visit" : "visits"), about \(Int(base.rounded())) min in light snow")
                    .font(.subheadline)
                let small = Int(model.estimate(for: property, inches: 1, defaultMinutes: 10).minutes.rounded())
                let medium = Int(model.estimate(for: property, inches: 4, defaultMinutes: 10).minutes.rounded())
                let large = Int(model.estimate(for: property, inches: 8, defaultMinutes: 10).minutes.rounded())
                Text("Estimate: 1 in \(small) min, 4 in \(medium) min, 8 in \(large) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No timed visits yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
