import Foundation
import SwiftData

@Model
final class Storm {
    var uuid: UUID?
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var snowInches: Double?

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.storm)
    var records: [ServiceRecord] = []

    // Hours are kept even if an old storm is deleted.
    @Relationship(deleteRule: .nullify, inverse: \Shift.storm)
    var shifts: [Shift] = []

    var isActive: Bool {
        endedAt == nil
    }

    init(name: String) {
        self.uuid = UUID()
        self.name = name
        self.startedAt = Date()
    }
}
