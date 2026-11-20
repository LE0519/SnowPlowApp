import SwiftUI
import SwiftData
import CoreLocation

struct CustomerEditView: View {
    @Environment(\.modelContext) private var modelContext
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
                .onDelete(perform: deleteProperties)

                Button {
                    addProperty()
                } label: {
                    Label("Add property", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(customer.name.isEmpty ? "New Customer" : customer.name)
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var isSearching = false
    @State private var message: String?

    private var addressIsEmpty: Bool {
        property.address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var statusText: String {
        if let message = message {
            return message
        }
        if let lat = property.latitude, let lon = property.longitude {
            return String(format: "Saved location: %.5f, %.5f", lat, lon)
        }
        return "No map location yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Address (include city and state)", text: $property.address, axis: .vertical)

            Stepper(
                "Arrival radius: \(Int(property.radiusMeters)) m",
                value: $property.radiusMeters,
                in: 50...500,
                step: 25
            )

            HStack {
                Button {
                    Task { await findOnMap() }
                } label: {
                    Label("Find on map", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(.borderless)
                .disabled(isSearching || addressIsEmpty)

                Spacer()

                if isSearching {
                    ProgressView()
                }
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .onChange(of: property.address) { _, _ in
            // If the address is edited, the old map location is no longer trustworthy.
            property.latitude = nil
            property.longitude = nil
            message = nil
        }
    }

    private func findOnMap() async {
        isSearching = true
        message = nil
        defer { isSearching = false }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(property.address)
            if let location = placemarks.first?.location {
                property.latitude = location.coordinate.latitude
                property.longitude = location.coordinate.longitude
                message = "Location found and saved."
            } else {
                message = "No match found. Try adding the city and state."
            }
        } catch {
            message = "Could not look up that address. Check your internet connection and try again."
        }
    }
}
