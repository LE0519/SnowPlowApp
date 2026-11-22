import SwiftUI
import SwiftData

struct NewCustomerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""
    @State private var address = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var radius: Double = 100

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let hasAddress = !address.trimmingCharacters(in: .whitespaces).isEmpty
        return hasName || hasAddress
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name (optional)", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("Property") {
                    AddressField(text: $address, latitude: $latitude, longitude: $longitude)
                    Stepper(
                        "Arrival radius: \(Int(radius)) m",
                        value: $radius,
                        in: 50...500,
                        step: 25
                    )
                }
            }
            .navigationTitle("New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let customer = Customer(
            name: name.trimmingCharacters(in: .whitespaces),
            notes: notes
        )
        modelContext.insert(customer)

        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        if !trimmedAddress.isEmpty {
            let property = Property(
                address: trimmedAddress,
                latitude: latitude,
                longitude: longitude,
                radiusMeters: radius
            )
            modelContext.insert(property)
            property.customer = customer
        }

        try? modelContext.save()
        dismiss()
    }
}
