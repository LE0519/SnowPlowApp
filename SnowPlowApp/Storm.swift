import Foundation
import SwiftData

@Model
final class Storm {
    var uuid: UUID?
    var name: String
    var startedAt: Date
    var endedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.storm)
    var records: [ServiceRecord] = []

    var isActive: Bool {
        endedAt == nil
    }

    init(name: String) {
        self.uuid = UUID()
        self.name = name
        self.startedAt = Date()
    }
}
