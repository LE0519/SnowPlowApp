import Foundation
import SwiftData

enum DataMaintenance {
    /// Gives every existing customer, property, and storm a unique ID if it does not have one yet.
    /// Records created before this update have no ID, so this runs each time the app opens.
    static func assignMissingIDs(in context: ModelContext) {
        var changed = false

        let customers = (try? context.fetch(FetchDescriptor<Customer>())) ?? []
        for customer in customers where customer.uuid == nil {
            customer.uuid = UUID()
            changed = true
        }

        let properties = (try? context.fetch(FetchDescriptor<Property>())) ?? []
        for property in properties where property.uuid == nil {
            property.uuid = UUID()
            changed = true
        }

        let storms = (try? context.fetch(FetchDescriptor<Storm>())) ?? []
        for storm in storms where storm.uuid == nil {
            storm.uuid = UUID()
            changed = true
        }

        if changed {
            try? context.save()
        }
    }
}
