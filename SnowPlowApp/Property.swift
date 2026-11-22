import Foundation
import SwiftData

@Model
final class Property {
    var uuid: UUID?
    var address: String
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double
    var isPriority: Bool?
    var deadlineMinutes: Int?
    var customer: Customer?

    @Relationship(deleteRule: .cascade, inverse: \ServiceRecord.property)
    var records: [ServiceRecord] = []

    init(address: String = "",
         latitude: Double? = nil,
         longitude: Double? = nil,
         radiusMeters: Double = 100) {
        self.uuid = UUID()
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}
