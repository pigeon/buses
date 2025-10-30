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

        if (maxX - minX) < minimumDimension {
            let adjustment = (minimumDimension - (maxX - minX)) / 2
            minX -= adjustment
            maxX += adjustment
        }

        if (maxY - minY) < minimumDimension {
            let adjustment = (minimumDimension - (maxY - minY)) / 2
            minY -= adjustment
            maxY += adjustment
        }

        var rect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let paddingRatio = 0.2
        let widthPadding = max(rect.size.width * paddingRatio, minimumDimension * 0.1)
        let heightPadding = max(rect.size.height * paddingRatio, minimumDimension * 0.1)

        rect = rect.insetBy(dx: -widthPadding, dy: -heightPadding)
        rect = rect.intersection(.world)

        cameraPosition = .rect(rect)
    }
}
