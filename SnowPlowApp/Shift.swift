import Foundation
import SwiftData

/// One stretch of work: from Clock In to Clock Out.
@Model
final class Shift {
    var uuid: UUID?
    var driverUID: String?
    var driverName: String
    var startedAt: Date
    var endedAt: Date?
    var storm: Storm?

    init(driverName: String, driverUID: String?) {
        self.uuid = UUID()
        self.driverName = driverName
        self.driverUID = driverUID
        self.startedAt = Date()
    }
}

enum ShiftActions {
    /// When a storm has ended, anyone still clocked in for it is clocked out at the storm's end time.
    /// The owner (or someone not in a team) closes everyone's shifts. A driver closes only their own.
    static func closeEndedStormShifts(in context: ModelContext) {
        let uid = CurrentUser.uid
        let isDriver = UserDefaults.standard.string(forKey: "team.role") == "driver"
        for shift in (try? context.fetch(FetchDescriptor<Shift>())) ?? [] {
            guard shift.endedAt == nil, let storm = shift.storm, let stormEnd = storm.endedAt else { continue }
            if !isDriver || shift.driverUID == uid {
                shift.endedAt = max(stormEnd, shift.startedAt)
            }
        }
    }
}
