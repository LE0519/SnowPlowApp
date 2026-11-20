import Foundation
import SwiftData

@Model
final class Property {
    var address: String
    var latitude: Double?
    var longitude: Double?
    var radiusMeters: Double
    var customer: Customer?

    init(address: String = "",
         latitude: Double? = nil,
         longitude: Double? = nil,
         radiusMeters: Double = 100) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}
