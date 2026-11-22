import SwiftUI
import SwiftData

struct CustomerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var showingNewCustomer = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(customers) { customer in
                    NavigationLink {
                        CustomerEditView(customer: customer)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(for: customer))
                                .font(.headline)
                            Text(subtitle(for: customer))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteCustomers)
            }
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView(
                        "No customers yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Tap + to add your first customer.")
                    )
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewCustomer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewCustomer) {
                NewCustomerView()
            }
            .onAppear(perform: removeEmptyCustomers)
        }
    }

    private func title(for customer: Customer) -> String {
        if !customer.name.isEmpty {
            return customer.name
        }
        if let first = customer.properties.first, !first.address.isEmpty {
            return first.address
        }
        return "(No name)"
    }

    private func subtitle(for customer: Customer) -> String {
        let count = customer.properties.count
        var text = count == 1 ? "1 property" : "\(count) properties"
        if !customer.name.isEmpty, let first = customer.properties.first, !first.address.isEmpty {
            text += " \u{2022} " + first.address
        }
        return text
    }

    private func deleteCustomers(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customers[index])
        }
    }

    // Cleans up customers that have no name and no properties.
    private func removeEmptyCustomers() {
        let empties = customers.filter {
            $0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.properties.isEmpty
        }
        for customer in empties {
            modelContext.delete(customer)
        }
    }
}
