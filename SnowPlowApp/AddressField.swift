import SwiftUI
import MapKit
import CoreLocation
import Observation

/// Gives address suggestions as you type.
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Favor results near where this phone last was.
        if let coordinate = CLLocationManager().location?.coordinate {
            completer.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }
    }

    func update(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 3 {
            suggestions = []
            completer.queryFragment = ""
        } else {
            completer.queryFragment = trimmed
        }
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

/// An address box that suggests addresses while you type and saves the map location when you pick one.
struct AddressField: View {
    @Binding var text: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?

    @State private var search = AddressSearch()
    @FocusState private var focused: Bool
    @State private var justPicked = false
    @State private var isSearching = false
    @State private var message: String?

    private var hasLocation: Bool {
        latitude != nil && longitude != nil
    }

    private var textIsEmpty: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Address (start typing)", text: $text)
                .focused($focused)
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    if justPicked {
                        justPicked = false
                        return
                    }
                    // The address was edited by hand, so the old map location no longer applies.
                    latitude = nil
                    longitude = nil
                    message = nil
                    search.update(newValue)
                }

            if focused && !search.suggestions.isEmpty {
                ForEach(Array(search.suggestions.prefix(5)), id: \.self) { suggestion in
                    Button {
                        pick(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if hasLocation {
                Label("Map location saved", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if !textIsEmpty && !focused {
                HStack {
                    Button {
                        Task { await findOnMap() }
                    } label: {
                        Label("Find on map", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isSearching)

                    if isSearching {
                        ProgressView()
                    }
                }
                Text(message ?? "No map location yet. Pick a suggestion or tap Find on map.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func pick(_ suggestion: MKLocalSearchCompletion) {
        let full = [suggestion.title, suggestion.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if full != text {
            justPicked = true
        }
        text = full
        focused = false
        search.clear()
        message = "Finding exact location..."

        let request = MKLocalSearch.Request(completion: suggestion)
        MKLocalSearch(request: request).start { response, error in
            DispatchQueue.main.async {
                if let item = response?.mapItems.first {
                    let coordinate = item.placemark.coordinate
                    latitude = coordinate.latitude
                    longitude = coordinate.longitude
                    message = nil
                } else {
                    message = "Could not find that location. Check your internet connection and try again."
                }
            }
        }
    }

    private func findOnMap() async {
        isSearching = true
        message = nil
        defer { isSearching = false }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(text)
            if let location = placemarks.first?.location {
                latitude = location.coordinate.latitude
                longitude = location.coordinate.longitude
            } else {
                message = "No match found. Try adding the city and state."
            }
        } catch {
            message = "Could not look up that address. Check your internet connection and try again."
        }
    }
}
