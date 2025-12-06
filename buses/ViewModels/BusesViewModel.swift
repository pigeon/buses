import Foundation
import _MapKit_SwiftUI
import Combine
import MapKit

@MainActor
final class BusesViewModel: ObservableObject {
    @Published var buses: [Bus] = []
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var timingStatusByBusID: [String: TimingStatus] = [:]
    private var timingRequestsInFlight: Set<String> = []

    func refresh(shouldUpdateCamera: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await BusService.shared.fetchBuses()
            buses = items
            if shouldUpdateCamera {
                updateCameraToFit(buses: items)
            }
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

    func fitToBuses(_ buses: [Bus]) {
        updateCameraToFit(buses: buses)
    }

    func timingStatus(for busID: String) -> TimingStatus? {
        timingStatusByBusID[busID]
    }

    func fetchTimingStatus(for bus: Bus) async {
        guard timingStatusByBusID[bus.id] == nil else { return }
        guard !timingRequestsInFlight.contains(bus.id) else { return }
        guard let journeyCode = bus.vehicleRef else { return }

        timingRequestsInFlight.insert(bus.id)
        defer { timingRequestsInFlight.remove(bus.id) }

        do {
            let status = try await BusService.shared.fetchTimingStatus(journeyCode: journeyCode)
            timingStatusByBusID[bus.id] = status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateCameraToFit(buses: [Bus]) {
        let coords = buses.compactMap { $0.coordinate }
        guard !coords.isEmpty else { return }

        if coords.count == 1, let c = coords.first {
            let region = MKCoordinateRegion(
                center: c,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            cameraPosition = .region(region)
            return
        }

        cameraPosition = .rect(mapRect(for: coords))
    }

    private func mapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        guard let firstPoint = coordinates.first.map(MKMapPoint.init) else {
            return .null
        }
        var minX = firstPoint.x
        var maxX = firstPoint.x
        var minY = firstPoint.y
        var maxY = firstPoint.y

        let minimumDimension: Double = 1_000
        let paddingRatio: Double = 0.2

        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let centerX = (maxX + minX) / 2
        let centerY = (maxY + minY) / 2

        let width = max(maxX - minX, minimumDimension)
        let height = max(maxY - minY, minimumDimension)

        let baseRect = MKMapRect(
            origin: MKMapPoint(x: centerX - width / 2, y: centerY - height / 2),
            size: MKMapSize(width: width, height: height)
        )

        let horizontalPadding = baseRect.size.width * paddingRatio
        let verticalPadding = baseRect.size.height * paddingRatio

        let paddedRect = baseRect
            .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
            .intersection(.world)

        return paddedRect
    }
}
