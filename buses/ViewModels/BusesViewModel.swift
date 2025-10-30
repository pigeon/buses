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

        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        for coordinate in coords {
            let point = MKMapPoint(coordinate)
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let minimumDimension: Double = 1_000
        let width = max(maxX - minX, minimumDimension)
        let height = max(maxY - minY, minimumDimension)

        let centerX = (maxX + minX) / 2
        let centerY = (maxY + minY) / 2

        let originX = centerX - (width / 2)
        let originY = centerY - (height / 2)

        var rect = MKMapRect(x: originX, y: originY, width: width, height: height)

        let paddingRatio = 0.2
        let paddedWidth = width * (1 + paddingRatio * 2)
        let paddedHeight = height * (1 + paddingRatio * 2)

        let paddedSize = MKMapSize(width: paddedWidth, height: paddedHeight)
        let paddedOrigin = MKMapPoint(x: centerX - paddedWidth / 2, y: centerY - paddedHeight / 2)

        rect = MKMapRect(origin: paddedOrigin, size: paddedSize)
        rect = rect.intersection(.world)

        cameraPosition = .rect(rect)
    }
}
