import SwiftUI
import SwiftData

struct CustomerEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Bindable var customer: Customer

    var body: some View {
        Form {
            Section("Customer") {
                TextField("Name", text: $customer.name)
                TextField("Notes", text: $customer.notes, axis: .vertical)
            }

            Section("Properties") {
                ForEach(customer.properties) { property in
                    PropertyRow(property: property)
                }
                .onDelete(perform: auth.canEditCustomers ? deleteProperties : nil)

                if auth.canEditCustomers {
                    Button {
                        addProperty()
                    } label: {
                        Label("Add property", systemImage: "plus.circle")
                    }
                }
            }
        }
        .navigationTitle(customer.name.isEmpty ? "Customer" : customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(!auth.canEditCustomers)
    }

    private func addProperty() {
        let property = Property()
        modelContext.insert(property)
        property.customer = customer
    }

    private func deleteProperties(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customer.properties[index])
        }
    }
}

struct PropertyRow: View {
    @Bindable var property: Property

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AddressField(
                text: $property.address,
                latitude: $property.latitude,
                longitude: $property.longitude
            )

            Stepper(
                "Arrival radius: \(Int(property.radiusMeters)) m",
                value: $property.radiusMeters,
                in: 50...500,
                step: 25
            )

            PriorityEditor(
                isPriority: Binding(
                    get: { property.isPriority ?? false },
                    set: { property.isPriority = $0 }
                ),
                deadlineMinutes: $property.deadlineMinutes
            )
        }
        .padding(.vertical, 4)
    }
}
