import Foundation
import SwiftData

@Model
final class ServiceRecord {
    var id: UUID
    var completedAt: Date
    var driverName: String
    var isAutomatic: Bool
    var storm: Storm?
    var property: Property?

    init(driverName: String, isAutomatic: Bool) {
        self.id = UUID()
        self.completedAt = Date()
        self.driverName = driverName
        self.isAutomatic = isAutomatic
    }
}
