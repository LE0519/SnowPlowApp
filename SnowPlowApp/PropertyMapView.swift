import SwiftUI
import SwiftData
import MapKit

struct MapPin: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let coordinate: CLLocationCoordinate2D
    let radius: Double
    let isDone: Bool
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
            let done = storm?.records.contains { $0.property === property } ?? false
            return MapPin(
                id: property.persistentModelID,
                name: name.isEmpty ? "(No name)" : name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                radius: property.radiusMeters,
                isDone: done
            )
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()

                ForEach(pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        Image(systemName: pin.isDone ? "checkmark.circle.fill" : "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(pin.isDone ? Color.green : Color.red)
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
