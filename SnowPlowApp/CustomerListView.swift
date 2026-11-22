import SwiftUI
import SwiftData

struct CustomerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
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
                .onDelete(perform: auth.canEditCustomers ? deleteCustomers : nil)
            }
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView(
                        "No customers yet",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text(auth.canEditCustomers
                                          ? "Tap + to add your first customer."
                                          : "Your team's customers appear here after syncing.")
                    )
                }
            }
            .navigationTitle("Customers")
            .toolbar {
                if auth.canEditCustomers {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingNewCustomer = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewCustomer) {
                NewCustomerView()
            }
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
}
