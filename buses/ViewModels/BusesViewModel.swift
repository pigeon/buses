import Foundation
import MapKit

@MainActor
final class BusesViewModel: ObservableObject {
    @Published var buses: [Bus] = []
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await BusService.shared.fetchBuses()
            buses = items
            updateCameraToFit(buses: items)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func focus(on bus: Bus) {
        guard let coord = bus.coordinate else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let region = MKCoordinateRegion(center: coord, span: span)
        cameraPosition = .region(region)
    }

    private func updateCameraToFit(buses: [Bus]) {
        let coords = buses.compactMap { $0.coordinate }
        guard !coords.isEmpty else { return }

        if coords.count == 1, let c = coords.first {
            let region = MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
            cameraPosition = .region(region)
            return
        }

        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }

        let latPad = max((maxLat - minLat) * 0.2, 0.02)
        let lonPad = max((maxLon - minLon) * 0.2, 0.02)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) + latPad,
            longitudeDelta: (maxLon - minLon) + lonPad
        )
        let region = MKCoordinateRegion(center: center, span: span)
        cameraPosition = .region(region)
    }
}
