import SwiftUI
import SwiftData
import MapKit

struct MapPin: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let coordinate: CLLocationCoordinate2D
    let radius: Double
}

struct PropertyMapView: View {
    @Query private var properties: [Property]
    @State private var position: MapCameraPosition = .automatic

    private var pins: [MapPin] {
        properties.compactMap { property in
            guard let lat = property.latitude, let lon = property.longitude else {
                return nil
            }
            let name = property.customer?.name ?? ""
            return MapPin(
                id: property.persistentModelID,
                name: name.isEmpty ? "(No name)" : name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                radius: property.radiusMeters
            )
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                ForEach(pins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.red)
                    }
                    MapCircle(center: pin.coordinate, radius: pin.radius)
                        .foregroundStyle(Color.blue.opacity(0.25))
                }
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
        }
    }
}
