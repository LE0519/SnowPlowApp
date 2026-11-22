import Foundation
import SwiftData
import Observation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

/// Copies customers, properties, storms, and completed-job records to the cloud and back.
/// Everything is stored under companies/main in Firestore. Your location is never sent.
@Observable
final class SyncService {
    var isEnabled = false
    var statusText = "Cloud sync is off."
    var detailText = ""

    private let collectionNames = ["customers", "properties", "storms", "records"]
    private var context: ModelContext?
    private var listeners: [ListenerRegistration] = []
    private var timer: Timer?
    private var isSigningIn = false
    private var firstSnapshotDone: Set<String> = []
    private var didInitialPush = false
    private var remoteIDs: [String: Set<UUID>] = [:]
    private var lastPushed: [UUID: String] = [:]
    private var pendingPropertyLinks: [UUID: UUID] = [:]
    private var pendingRecordLinks: [UUID: RecordLink] = [:]

    private struct RecordLink {
        let propertyID: UUID?
        let stormID: UUID?
    }

    private struct Change {
        let id: UUID
        let removed: Bool
        let data: [String: Any]
    }

    // MARK: - Turning sync on and off

    func configure(context: ModelContext) {
        self.context = context
        if UserDefaults.standard.bool(forKey: "cloudSyncEnabled"), !isEnabled {
            start()
        }
    }

    func start() {
        guard context != nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            statusText = "The Firebase settings file is missing from this build."
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isEnabled = true
        statusText = "Connecting..."

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        removeListeners()
        statusText = "Cloud sync is off."
        detailText = ""
    }

    func syncNow() {
        tick()
    }

    private func removeListeners() {
        for listener in listeners {
            listener.remove()
        }
        listeners = []
        firstSnapshotDone = []
        didInitialPush = false
        remoteIDs = [:]
    }

    // MARK: - Regular check

    private func tick() {
        guard isEnabled else { return }

        if Auth.auth().currentUser == nil {
            signIn()
            return
        }
        if listeners.isEmpty {
            attachListeners()
        }
        pushChanges()
    }

    private func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        statusText = "Signing in..."
        Auth.auth().signInAnonymously { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSigningIn = false
                if let error = error {
                    self.statusText = "Waiting to sign in: \(error.localizedDescription)"
                } else {
                    self.tick()
                }
            }
        }
    }

    private func attachListeners() {
        let company = Firestore.firestore().collection("companies").document("main")
        for name in collectionNames {
            let listener = company.collection(name).addSnapshotListener { [weak self] snapshot, error in
                self?.handle(name, snapshot, error)
            }
            listeners.append(listener)
        }
    }

    // MARK: - Cloud to phone

    private func handle(_ name: String, _ snapshot: QuerySnapshot?, _ error: Error?) {
        if let error = error {
            statusText = "Sync problem: \(error.localizedDescription)"
            removeListeners()
            return
        }
        guard let snapshot = snapshot, let context = context else { return }

        var ids = remoteIDs[name] ?? []
        let changes = collect(snapshot, ids: &ids)
        remoteIDs[name] = ids

        switch name {
        case "customers":
            applyCustomers(changes, context: context)
        case "properties":
            applyProperties(changes, context: context)
        case "storms":
            applyStorms(changes, context: context)
        default:
            applyRecords(changes, context: context)
        }

        resolveLinks(context: context)
        try? context.save()

        firstSnapshotDone.insert(name)
        if firstSnapshotDone.count == collectionNames.count && !didInitialPush {
            didInitialPush = true
            pushChanges()
        }
        updateStatus()
    }

    /// Turns a cloud snapshot into a list of real changes, skipping echoes of our own writes.
    private func collect(_ snapshot: QuerySnapshot, ids: inout Set<UUID>) -> [Change] {
        var result: [Change] = []
        for change in snapshot.documentChanges {
            guard let id = UUID(uuidString: change.document.documentID) else { continue }
            switch change.type {
            case .added, .modified:
                ids.insert(id)
                if change.document.metadata.hasPendingWrites {
                    continue
                }
                let data = change.document.data()
                let sig = signature(of: data)
                if lastPushed[id] == sig {
                    continue
                }
                lastPushed[id] = sig
                result.append(Change(id: id, removed: false, data: data))
            case .removed:
                ids.remove(id)
                lastPushed[id] = nil
                result.append(Change(id: id, removed: true, data: [:]))
            }
        }
        return result
    }

    private func applyCustomers(_ changes: [Change], context: ModelContext) {
        if changes.isEmpty { return }
        var byID: [UUID: Customer] = [:]
        for customer in (try? context.fetch(FetchDescriptor<Customer>())) ?? [] {
            if let id = customer.uuid { byID[id] = customer }
        }
        for change in changes {
            if change.removed {
                if let existing = byID[change.id] { context.delete(existing) }
                continue
            }
            let customer: Customer
            if let existing = byID[change.id] {
                customer = existing
            } else {
                customer = Customer()
                customer.uuid = change.id
                context.insert(customer)
                byID[change.id] = customer
            }
            customer.name = change.data["name"] as? String ?? ""
            customer.notes = change.data["notes"] as? String ?? ""
            if let created = change.data["createdAt"] as? Timestamp {
                customer.createdAt = created.dateValue()
            }
        }
    }

    private func applyProperties(_ changes: [Change], context: ModelContext) {
        if changes.isEmpty { return }
        var byID: [UUID: Property] = [:]
        for property in (try? context.fetch(FetchDescriptor<Property>())) ?? [] {
            if let id = property.uuid { byID[id] = property }
        }
        for change in changes {
            if change.removed {
                pendingPropertyLinks[change.id] = nil
                if let existing = byID[change.id] { context.delete(existing) }
                continue
            }
            let property: Property
            if let existing = byID[change.id] {
                property = existing
            } else {
                property = Property()
                property.uuid = change.id
                context.insert(property)
                byID[change.id] = property
            }
            property.address = change.data["address"] as? String ?? ""
            property.radiusMeters = change.data["radiusMeters"] as? Double ?? 100
            property.latitude = change.data["latitude"] as? Double
            property.longitude = change.data["longitude"] as? Double
            property.isPriority = (change.data["isPriority"] as? Bool) ?? false
            property.deadlineMinutes = change.data["deadlineMinutes"] as? Int
            if let customerText = change.data["customerID"] as? String,
               let customerID = UUID(uuidString: customerText) {
                pendingPropertyLinks[change.id] = customerID
            } else {
                pendingPropertyLinks[change.id] = nil
                property.customer = nil
            }
        }
    }

    private func applyStorms(_ changes: [Change], context: ModelContext) {
        if changes.isEmpty { return }
        var byID: [UUID: Storm] = [:]
        for storm in (try? context.fetch(FetchDescriptor<Storm>())) ?? [] {
            if let id = storm.uuid { byID[id] = storm }
        }
        for change in changes {
            if change.removed {
                if let existing = byID[change.id] { context.delete(existing) }
                continue
            }
            let storm: Storm
            if let existing = byID[change.id] {
                storm = existing
            } else {
                storm = Storm(name: "")
                storm.uuid = change.id
                context.insert(storm)
                byID[change.id] = storm
            }
            storm.name = change.data["name"] as? String ?? ""
            if let started = change.data["startedAt"] as? Timestamp {
                storm.startedAt = started.dateValue()
            }
            storm.endedAt = (change.data["endedAt"] as? Timestamp)?.dateValue()
        }
    }

    private func applyRecords(_ changes: [Change], context: ModelContext) {
        if changes.isEmpty { return }
        var byID: [UUID: ServiceRecord] = [:]
        for record in (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? [] {
            byID[record.id] = record
        }
        for change in changes {
            if change.removed {
                pendingRecordLinks[change.id] = nil
                if let existing = byID[change.id] { context.delete(existing) }
                continue
            }
            let record: ServiceRecord
            if let existing = byID[change.id] {
                record = existing
            } else {
                record = ServiceRecord(driverName: "", isAutomatic: false)
                record.id = change.id
                context.insert(record)
                byID[change.id] = record
            }
            record.driverName = change.data["driverName"] as? String ?? ""
            record.isAutomatic = change.data["isAutomatic"] as? Bool ?? false
            if let completed = change.data["completedAt"] as? Timestamp {
                record.completedAt = completed.dateValue()
            }
            let propertyID = UUID(uuidString: change.data["propertyID"] as? String ?? "")
            let stormID = UUID(uuidString: change.data["stormID"] as? String ?? "")
            pendingRecordLinks[change.id] = RecordLink(propertyID: propertyID, stormID: stormID)
        }
    }

    /// Connects properties to customers, and records to properties and storms, once both sides exist.
    private func resolveLinks(context: ModelContext) {
        if !pendingPropertyLinks.isEmpty {
            var customers: [UUID: Customer] = [:]
            for customer in (try? context.fetch(FetchDescriptor<Customer>())) ?? [] {
                if let id = customer.uuid { customers[id] = customer }
            }
            var properties: [UUID: Property] = [:]
            for property in (try? context.fetch(FetchDescriptor<Property>())) ?? [] {
                if let id = property.uuid { properties[id] = property }
            }
            for (propertyID, customerID) in pendingPropertyLinks {
                if let property = properties[propertyID], let customer = customers[customerID] {
                    if property.customer !== customer {
                        property.customer = customer
                    }
                    pendingPropertyLinks[propertyID] = nil
                }
            }
        }

        if !pendingRecordLinks.isEmpty {
            var properties: [UUID: Property] = [:]
            for property in (try? context.fetch(FetchDescriptor<Property>())) ?? [] {
                if let id = property.uuid { properties[id] = property }
            }
            var storms: [UUID: Storm] = [:]
            for storm in (try? context.fetch(FetchDescriptor<Storm>())) ?? [] {
                if let id = storm.uuid { storms[id] = storm }
            }
            var records: [UUID: ServiceRecord] = [:]
            for record in (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? [] {
                records[record.id] = record
            }
            for (recordID, link) in pendingRecordLinks {
                guard let record = records[recordID] else {
                    pendingRecordLinks[recordID] = nil
                    continue
                }
                guard let propertyID = link.propertyID, let stormID = link.stormID,
                      let property = properties[propertyID], let storm = storms[stormID] else {
                    continue
                }
                if record.property !== property { record.property = property }
                if record.storm !== storm { record.storm = storm }
                pendingRecordLinks[recordID] = nil
            }
        }
    }

    // MARK: - Phone to cloud

    private func pushChanges() {
        guard isEnabled, let context = context,
              firstSnapshotDone.count == collectionNames.count else { return }

        let company = Firestore.firestore().collection("companies").document("main")
        var localIDs: [String: Set<UUID>] = [:]

        // Records an object as existing on this phone and sends it only if it changed.
        func send(_ name: String, _ id: UUID, _ data: [String: Any]?) {
            localIDs[name, default: []].insert(id)
            guard let data = data else { return }
            let sig = signature(of: data)
            if lastPushed[id] == sig { return }
            lastPushed[id] = sig
            company.collection(name).document(id.uuidString).setData(data)
        }

        for customer in (try? context.fetch(FetchDescriptor<Customer>())) ?? [] {
            guard let id = customer.uuid else { continue }
            send("customers", id, [
                "name": customer.name,
                "notes": customer.notes,
                "createdAt": Timestamp(date: customer.createdAt)
            ])
        }

        for property in (try? context.fetch(FetchDescriptor<Property>())) ?? [] {
            guard let id = property.uuid else { continue }
            if pendingPropertyLinks[id] != nil {
                send("properties", id, nil)
                continue
            }
            var data: [String: Any] = [
                "address": property.address,
                "radiusMeters": property.radiusMeters
            ]
            if let lat = property.latitude { data["latitude"] = lat }
            if let lon = property.longitude { data["longitude"] = lon }
            if let customerID = property.customer?.uuid { data["customerID"] = customerID.uuidString }
            if property.isPriorityFlag { data["isPriority"] = true }
            if let deadline = property.deadlineMinutes { data["deadlineMinutes"] = deadline }
            send("properties", id, data)
        }

        for storm in (try? context.fetch(FetchDescriptor<Storm>())) ?? [] {
            guard let id = storm.uuid else { continue }
            var data: [String: Any] = [
                "name": storm.name,
                "startedAt": Timestamp(date: storm.startedAt)
            ]
            if let ended = storm.endedAt { data["endedAt"] = Timestamp(date: ended) }
            send("storms", id, data)
        }

        for record in (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? [] {
            if pendingRecordLinks[record.id] != nil {
                send("records", record.id, nil)
                continue
            }
            var data: [String: Any] = [
                "completedAt": Timestamp(date: record.completedAt),
                "driverName": record.driverName,
                "isAutomatic": record.isAutomatic
            ]
            if let propertyID = record.property?.uuid { data["propertyID"] = propertyID.uuidString }
            if let stormID = record.storm?.uuid { data["stormID"] = stormID.uuidString }
            send("records", record.id, data)
        }

        // Things deleted on this phone get deleted in the cloud too.
        // Safety: if this phone looks completely empty, do not delete anything.
        let phoneHasAnything = localIDs.values.contains { !$0.isEmpty }
        if phoneHasAnything {
            for name in collectionNames {
                let local = localIDs[name] ?? []
                for id in remoteIDs[name] ?? [] where !local.contains(id) {
                    company.collection(name).document(id.uuidString).delete()
                    lastPushed[id] = nil
                }
            }
        }

        updateStatus()
    }

    // MARK: - Helpers

    private func updateStatus() {
        let time = Date().formatted(date: .omitted, time: .shortened)
        statusText = "Cloud sync is on. Last check \(time)."
        let customers = remoteIDs["customers"]?.count ?? 0
        let properties = remoteIDs["properties"]?.count ?? 0
        let storms = remoteIDs["storms"]?.count ?? 0
        let records = remoteIDs["records"]?.count ?? 0
        detailText = "In the cloud: \(customers) customers, \(properties) properties, \(storms) storms, \(records) completed jobs."
    }

    /// A text fingerprint of a document, used to tell whether anything really changed.
    private func signature(of data: [String: Any]) -> String {
        var parts: [String] = []
        for key in data.keys.sorted() {
            let value = data[key]
            let text: String
            if let timestamp = value as? Timestamp {
                text = String(Int((timestamp.dateValue().timeIntervalSince1970 * 1000).rounded()))
            } else if let string = value as? String {
                text = string
            } else if let number = value as? NSNumber {
                if key == "isAutomatic" || key == "isPriority" {
                    text = number.boolValue ? "true" : "false"
                } else {
                    text = String(format: "%.7f", number.doubleValue)
                }
            } else {
                text = "\(value ?? "")"
            }
            parts.append("\(key)=\(text)")
        }
        return parts.joined(separator: "|")
    }
}
