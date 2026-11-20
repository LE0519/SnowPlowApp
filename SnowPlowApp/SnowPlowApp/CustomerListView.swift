import SwiftUI
import SwiftData

struct CustomerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var newCustomer: Customer?

    var body: some View {
        NavigationStack {
            List {
                ForEach(customers) { customer in
                    NavigationLink {
                        CustomerEditView(customer: customer)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(customer.name.isEmpty ? "(No name)" : customer.name)
                                .font(.headline)
                            Text(propertyCountText(for: customer))
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
                        addCustomer()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $newCustomer) { customer in
                CustomerEditView(customer: customer)
            }
            .onAppear(perform: removeEmptyCustomers)
        }
    }

    private func propertyCountText(for customer: Customer) -> String {
        let count = customer.properties.count
        return count == 1 ? "1 property" : "\(count) properties"
    }

    private func addCustomer() {
        let customer = Customer()
        modelContext.insert(customer)
        newCustomer = customer
    }

    private func deleteCustomers(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customers[index])
        }
    }

    // Cleans up customers that were created with + but never given a name.
    private func removeEmptyCustomers() {
        let empties = customers.filter {
            $0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.properties.isEmpty
        }
        for customer in empties {
            modelContext.delete(customer)
        }
    }
}
