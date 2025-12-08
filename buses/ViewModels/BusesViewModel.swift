import Foundation
import Combine
import _MapKit_SwiftUI
import MapKit

@MainActor
final class BusesViewModel: ObservableObject {
    enum CameraMode {
        case follow
        case manual
    }

    private struct CachedTimingStatus {
        let status: TimingStatus?
        let fetchedAt: Date
    }

    private let service: BusServiceProtocol
    private let timingStatusTTL: TimeInterval
    private let dateProvider: () -> Date
    @Published var buses: [Bus] = []
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var focusedBusID: Bus.ID?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var cameraMode: CameraMode = .follow
    @Published private var timingStatusByBusID: [String: CachedTimingStatus] = [:]
    private var timingRequestsInFlight: Set<String> = []

    init(
        service: BusServiceProtocol = BusService.shared,
        timingStatusTTL: TimeInterval = 300,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.timingStatusTTL = timingStatusTTL
        self.dateProvider = dateProvider
    }

    func refresh(shouldUpdateCamera: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await service.fetchBuses()
            buses = items
            pruneCachedTimingStatuses(with: items)

            if shouldUpdateCamera && cameraMode == .follow {
                updateCameraToFit(buses: items)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func focus(on bus: Bus) {
        focusedBusID = bus.id
        cameraMode = .follow
        guard let coord = bus.coordinate else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let region = MKCoordinateRegion(center: coord, span: span)
        cameraPosition = .region(region)
    }

    func fitToBuses(_ buses: [Bus]) {
        cameraMode = .follow
        updateCameraToFit(buses: buses)
    }

    func timingStatus(for busID: String) -> TimingStatus? {
        guard let cached = timingStatusByBusID[busID] else { return nil }
        guard !isTimingStatusStale(cached) else {
            timingStatusByBusID.removeValue(forKey: busID)
            return nil
        }
        return cached.status
    }

    func fetchTimingStatus(for bus: Bus) async {
        if let cached = timingStatusByBusID[bus.id], !isTimingStatusStale(cached) {
            return
        }

        guard !timingRequestsInFlight.contains(bus.id) else { return }

        guard let journeyCode = bus.journeyCode ?? bus.vehicleRef else {
            timingStatusByBusID[bus.id] = CachedTimingStatus(status: TimingStatus(minutes: nil, status: nil), fetchedAt: dateProvider())
            return
        }

        timingRequestsInFlight.insert(bus.id)
        defer { timingRequestsInFlight.remove(bus.id) }

        do {
            let status = try await service.fetchTimingStatus(journeyCode: journeyCode)
            timingStatusByBusID[bus.id] = CachedTimingStatus(status: status ?? TimingStatus(minutes: nil, status: nil), fetchedAt: dateProvider())
        } catch {
            timingStatusByBusID[bus.id] = CachedTimingStatus(status: TimingStatus(minutes: nil, status: nil), fetchedAt: dateProvider())
            errorMessage = error.localizedDescription
        }
    }

    func enterManualCameraMode() {
        cameraMode = .manual
    }

    func resetCamera(using buses: [Bus]) {
        cameraMode = .follow

        if let focusedBusID,
           let bus = buses.first(where: { $0.id == focusedBusID }) {
            focus(on: bus)
        } else {
            fitToBuses(buses)
        }
    }

    func clearFocusIfMissing(in buses: [Bus]) {
        guard let focusedBusID else { return }
        guard buses.contains(where: { $0.id == focusedBusID }) else {
            focusedBusID = nil
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

    private func isTimingStatusStale(_ cached: CachedTimingStatus) -> Bool {
        dateProvider().timeIntervalSince(cached.fetchedAt) > timingStatusTTL
    }

    private func pruneCachedTimingStatuses(with buses: [Bus]) {
        let validIDs = Set(buses.map { $0.id })
        timingStatusByBusID = timingStatusByBusID.filter { validIDs.contains($0.key) && !isTimingStatusStale($0.value) }
    }
}
