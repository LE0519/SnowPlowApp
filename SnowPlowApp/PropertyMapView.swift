import SwiftUI
import SwiftData
import MapKit

struct MapPin: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let coordinate: CLLocationCoordinate2D
    let radius: Double
    let isDone: Bool
    let isPriority: Bool
    let isInProgress: Bool
}

struct PropertyMapView: View {
    @Environment(LocationService.self) private var locationService
    @Query private var properties: [Property]
    @Query private var storms: [Storm]
    @State private var position: MapCameraPosition = .automatic

    private var activeStorm: Storm? {
        storms.first { $0.isActive }
    }

    private var pins: [MapPin] {
        let storm = activeStorm
        return properties.compactMap { property in
            guard let lat = property.latitude, let lon = property.longitude else {
                return nil
            }
            let name = property.customer?.name ?? ""
            let done = storm.map { property.isDone(in: $0) } ?? false
            let working = storm.map { property.isInProgress(in: $0) } ?? false
            return MapPin(
                id: property.persistentModelID,
                name: name.isEmpty ? "(No name)" : name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                radius: property.radiusMeters,
                isDone: done,
                isPriority: property.isPriorityFlag,
                isInProgress: working
            )
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()

                ForEach(pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        Image(systemName: pin.isDone ? "checkmark.circle.fill" : (pin.isInProgress ? "clock.circle.fill" : (pin.isPriority ? "star.circle.fill" : "mappin.circle.fill")))
                            .font(.title)
                            .foregroundStyle(pin.isDone ? Color.green : (pin.isInProgress ? Color.blue : (pin.isPriority ? Color.orange : Color.red)))
                    }
                    MapCircle(center: pin.coordinate, radius: pin.radius)
                        .foregroundStyle(Color.blue.opacity(0.25))
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .overlay {
                if pins.isEmpty {
                    Text("No properties on the map yet.\nOpen a customer's property and tap \"Find on map\".")
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                locationService.requestPermissionIfNeeded()
            }
        }
    }
}
