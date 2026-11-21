import Foundation
import SwiftData

@Model
final class Customer {
    var uuid: UUID?
    var name: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Property.customer)
    var properties: [Property] = []

    init(name: String = "", notes: String = "") {
        self.uuid = UUID()
        self.name = name
        self.notes = notes
        self.createdAt = Date()
    }
}
