import MapKit
import SwiftUI

struct MetadataMapView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var location: DecoyLocation
    @State private var position: MapCameraPosition
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var search: MKLocalSearch?
    @State private var searchGeneration = UUID()
    @State private var latitude: String
    @State private var longitude: String
    let choose: (DecoyLocation) -> Void

    init(location: DecoyLocation, choose: @escaping (DecoyLocation) -> Void) {
        _location = State(initialValue: location)
        _latitude = State(initialValue: String(format: "%.5f", location.latitude))
        _longitude = State(initialValue: String(format: "%.5f", location.longitude))
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))))
        self.choose = choose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search a city or place", text: $query)
                        .submitLabel(.search).onSubmit { Task { await searchPlaces() } }
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("metadata.placeSearch")
                    if isSearching { ProgressView() }
                    else { Button("Search") { Task { await searchPlaces() } }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
                .padding(14).background(.regularMaterial)
                if !results.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                                Button {
                                    select(item.placemark.coordinate, name: item.name ?? "Selected place",
                                           zone: item.timeZone?.identifier ?? "GMT")
                                    results = []
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name ?? "Place").foregroundStyle(.primary)
                                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        Spacer()
                                        Image(systemName: "mappin").foregroundStyle(NoctGalleryTheme.accent)
                                    }.padding(12)
                                }
                                Divider()
                            }
                        }
                    }.frame(height: min(180, CGFloat(results.count) * 76))
                }
                MapReader { proxy in
                    Map(position: $position) {
                        Marker(location.name, coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                            .tint(NoctGalleryTheme.accent)
                    }
                    .mapControls { MapCompass(); MapScaleView() }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            select(coordinate, name: "Dropped pin", zone: "GMT", moveCamera: false)
                        }
                    }
                    .accessibilityIdentifier("metadata.map")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(location.name).font(.headline).lineLimit(2)
                    HStack(spacing: 12) {
                        coordinateField("Latitude", text: $latitude)
                        coordinateField("Longitude", text: $longitude)
                        Button("Set") { setCoordinates() }.buttonStyle(.bordered)
                    }
                    Text("Tap to place the pin. Uses Apple Maps, without requesting your location.")
                        .font(.caption).foregroundStyle(.secondary)
                    if location.timeZoneIdentifier == "GMT" {
                        Text("Pins use UTC. Search results use local time.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let searchError { Text(searchError).font(.caption).foregroundStyle(.red) }
                }
                .padding(16).background(.regularMaterial)
            }
            .navigationTitle("Choose a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Location") { choose(location); dismiss() }
                        .fontWeight(.semibold).disabled(!location.isValid)
                        .accessibilityIdentifier("metadata.useLocation")
                }
            }
            .onDisappear { search?.cancel(); searchGeneration = UUID() }
        }
    }

    private func coordinateField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
        }
    }

    private func select(_ coordinate: CLLocationCoordinate2D, name: String, zone: String, moveCamera: Bool = true) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        location = DecoyLocation(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZoneIdentifier: zone)
        latitude = String(format: "%.5f", coordinate.latitude)
        longitude = String(format: "%.5f", coordinate.longitude)
        searchError = nil
        if moveCamera { position = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035))) }
    }

    private func setCoordinates() {
        guard let lat = Double(latitude), let lon = Double(longitude), lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon) else { searchError = "Enter valid latitude and longitude."; return }
        select(CLLocationCoordinate2D(latitude: lat, longitude: lon), name: "Selected coordinates", zone: "GMT")
    }

    private func searchPlaces() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        search?.cancel()
        let generation = UUID()
        searchGeneration = generation
        isSearching = true
        searchError = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        let operation = MKLocalSearch(request: request)
        search = operation
        do {
            let response = try await operation.start()
            guard generation == searchGeneration else { return }
            results = Array(response.mapItems.prefix(8))
            if results.isEmpty { searchError = "No places found. Try another name or drop a pin." }
        } catch { if generation == searchGeneration { searchError = "Search is unavailable. You can still set coordinates or move the pin." } }
        if generation == searchGeneration { isSearching = false }
    }
}
