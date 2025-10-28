//
//  ContentView.swift
//  buses
//
//  Created by Dmytro Golub on 28/10/2025.
//

// GoCoachBusesMapApp.swift
// SwiftUI single-file demo that fetches Go Coach widget buses
// and displays them on a Map zoomed to the bounding box.
//
// Requires iOS 17+ (Map/MapCameraPosition).
// If the endpoint enforces a Referer/WAF token, see the notes in BusService.

import SwiftUI
import MapKit
import Combine


// MARK: - Model
struct Bus: Decodable, Identifiable, Equatable {
    // Coding keys map the incoming JSON
    enum CodingKeys: String, CodingKey {
        case routeDescription = "RouteDescription"
        case destinationStopName = "DestinationStopName"
        case destinationStopLocality = "DestinationStopLocality"
        case destinationStopFullName = "DestinationStopFullName"
        case lastUpdated = "LastUpdated"
        case occupancy = "Occupancy"
        case departureTime = "DepartureTime"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case recordedAtTime = "RecordedAtTime"
        case validUntilTime = "ValidUntilTime"
        case lineRef = "LineRef"
        case directionRef = "DirectionRef"
        case publishedLineName = "PublishedLineName"
        case operatorRef = "OperatorRef"
        case bearing = "Bearing"
        case blockRef = "BlockRef"
        case ticketMachineServiceCode = "TicketMachineServiceCode"
        case journeyCode = "JourneyCode"
        case dbCreated = "DbCreated"
        case dataSetId = "DataSetId"
        case destinationRef = "DestinationRef"
        case nextStopName = "NextStopName"
        case nextStopLocality = "NextStopLocality"
        case nextStopFullName = "NextStopFullName"
        case stopPointRef = "StopPointRef"
        case currentStopName = "CurrentStopName"
        case currentStopLocality = "CurrentStopLocality"
        case currentStopFullName = "CurrentStopFullName"
        case vehicleAtStop = "VehicleAtStop"
        case visitNumber = "VisitNumber"
        case vehicleRef = "VehicleRef"
        case destination = "Destination"
        case timingStatus = "TimingStatus"
    }

    struct Occupancy: Decodable, Equatable {
        let seatedCapacity: Int?
        let seatedOccupancy: Int?
        let wheelchairCapacity: Int?
        let wheelchairOccupancy: Int?
        let status: Int?

        enum CodingKeys: String, CodingKey {
            case seatedCapacity = "SeatedCapacity"
            case seatedOccupancy = "SeatedOccupancy"
            case wheelchairCapacity = "WheelchairCapacity"
            case wheelchairOccupancy = "WheelchairOccupancy"
            case status = "Status"
        }
    }

    // Raw fields
    let routeDescription: String?
    let destinationStopName: String?
    let destinationStopLocality: String?
    let destinationStopFullName: String?
    let lastUpdated: Date?
    let occupancy: Occupancy?
    let departureTimeISO: Date?
    let latitudeString: String
    let longitudeString: String
    let recordedAtTimeISO: Date?
    let validUntilTimeISO: Date?
    let lineRef: String?
    let directionRef: String?
    let publishedLineName: String?
    let operatorRef: String?
    let bearing: String?
    let blockRef: String?
    let ticketMachineServiceCode: String?
    let journeyCode: String?
    let dbCreated: Date?
    let dataSetId: Int?
    let destinationRef: String?
    let nextStopName: String?
    let nextStopLocality: String?
    let nextStopFullName: String?
    let stopPointRef: String?
    let currentStopName: String?
    let currentStopLocality: String?
    let currentStopFullName: String?
    let vehicleAtStop: Bool?
    let visitNumber: String?
    let vehicleRef: String?
    let destination: String?
    let timingStatus: String?
    private let stableIdentifier: String

    // Stable identity across refreshes: vehicleRef + lineRef preferred
    var id: String { stableIdentifier }

    // Convenience
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitudeString), let lon = Double(longitudeString) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var title: String {
        if let line = publishedLineName ?? lineRef { return line }
        return vehicleRef ?? "Bus"
    }

    var subtitle: String {
        if let dest = destinationStopFullName ?? destinationStopName { return dest }
        return currentStopFullName ?? currentStopName ?? ""
    }

    var lineBadgeText: String? {
        guard let name = publishedLineName ?? lineRef else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(4))
    }

    var routeLabel: String? {
        let trimmedName = publishedLineName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmedName, !name.isEmpty { return name }
        let trimmedRef = lineRef?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ref = trimmedRef, !ref.isEmpty { return ref }
        return nil
    }

    var destinationLabel: String {
        subtitle.isEmpty ? (destination ?? "") : subtitle
    }

    var occupancyDescription: String {
        switch occupancyLevel {
        case .unknown:
            return "Occupancy: Unknown"
        case .plenty:
            return "Occupancy: Many seats"
        case .limited:
            return "Occupancy: Few seats"
        case .full:
            return "Occupancy: Full"
        }
    }

    fileprivate var occupancyLevel: BusOccupancyLevel {
        guard let capacity = occupancy?.seatedCapacity, capacity > 0,
              let seated = occupancy?.seatedOccupancy else {
            return .unknown
        }
        let ratio = Double(seated) / Double(capacity)
        if ratio < 0.4 { return .plenty }
        if ratio < 0.85 { return .limited }
        return .full
    }

    // Custom decoder to handle mixed date formats and string coords
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routeDescription = try c.decodeIfPresent(String.self, forKey: .routeDescription)
        destinationStopName = try c.decodeIfPresent(String.self, forKey: .destinationStopName)
        destinationStopLocality = try c.decodeIfPresent(String.self, forKey: .destinationStopLocality)
        destinationStopFullName = try c.decodeIfPresent(String.self, forKey: .destinationStopFullName)
        occupancy = try c.decodeIfPresent(Occupancy.self, forKey: .occupancy)

        // Dates
        lastUpdated = try Bus.decodeDotNetDateOrNil(from: c, key: .lastUpdated)
        dbCreated = try Bus.decodeDotNetDateOrNil(from: c, key: .dbCreated)
        departureTimeISO = try Bus.decodeISO8601OrNil(from: c, key: .departureTime)
        recordedAtTimeISO = try Bus.decodeISO8601OrNil(from: c, key: .recordedAtTime)
        validUntilTimeISO = try Bus.decodeISO8601OrNil(from: c, key: .validUntilTime)

        // Strings
        latitudeString = try c.decode(String.self, forKey: .latitude)
        longitudeString = try c.decode(String.self, forKey: .longitude)
        lineRef = try c.decodeIfPresent(String.self, forKey: .lineRef)
        directionRef = try c.decodeIfPresent(String.self, forKey: .directionRef)
        publishedLineName = try c.decodeIfPresent(String.self, forKey: .publishedLineName)
        operatorRef = try c.decodeIfPresent(String.self, forKey: .operatorRef)
        bearing = try c.decodeIfPresent(String.self, forKey: .bearing)
        blockRef = try c.decodeIfPresent(String.self, forKey: .blockRef)
        ticketMachineServiceCode = try c.decodeIfPresent(String.self, forKey: .ticketMachineServiceCode)
        journeyCode = try c.decodeIfPresent(String.self, forKey: .journeyCode)
        dataSetId = try c.decodeIfPresent(Int.self, forKey: .dataSetId)
        destinationRef = try c.decodeIfPresent(String.self, forKey: .destinationRef)
        nextStopName = try c.decodeIfPresent(String.self, forKey: .nextStopName)
        nextStopLocality = try c.decodeIfPresent(String.self, forKey: .nextStopLocality)
        nextStopFullName = try c.decodeIfPresent(String.self, forKey: .nextStopFullName)
        stopPointRef = try c.decodeIfPresent(String.self, forKey: .stopPointRef)
        currentStopName = try c.decodeIfPresent(String.self, forKey: .currentStopName)
        currentStopLocality = try c.decodeIfPresent(String.self, forKey: .currentStopLocality)
        currentStopFullName = try c.decodeIfPresent(String.self, forKey: .currentStopFullName)
        vehicleAtStop = try c.decodeIfPresent(Bool.self, forKey: .vehicleAtStop)
        visitNumber = try c.decodeIfPresent(String.self, forKey: .visitNumber)
        vehicleRef = try c.decodeIfPresent(String.self, forKey: .vehicleRef)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        timingStatus = try c.decodeIfPresent(String.self, forKey: .timingStatus)

        stableIdentifier = Bus.makeStableIdentifier(
            vehicleRef: vehicleRef,
            lineRef: lineRef,
            journeyCode: journeyCode,
            ticketMachineServiceCode: ticketMachineServiceCode,
            blockRef: blockRef,
            stopPointRef: stopPointRef,
            latitude: latitudeString,
            longitude: longitudeString,
            recordedAt: recordedAtTimeISO,
            validUntil: validUntilTimeISO
        )
    }

    private static func makeStableIdentifier(
        vehicleRef: String?,
        lineRef: String?,
        journeyCode: String?,
        ticketMachineServiceCode: String?,
        blockRef: String?,
        stopPointRef: String?,
        latitude: String,
        longitude: String,
        recordedAt: Date?,
        validUntil: Date?
    ) -> String {
        if let vehicleRef, let lineRef {
            return "\(vehicleRef)_\(lineRef)"
        }
        if let vehicleRef {
            return vehicleRef
        }
        if let journeyCode, !journeyCode.isEmpty {
            return journeyCode
        }
        if let ticketMachineServiceCode, !ticketMachineServiceCode.isEmpty {
            return ticketMachineServiceCode
        }
        if let blockRef, !blockRef.isEmpty {
            return blockRef
        }
        if let stopPointRef, !stopPointRef.isEmpty {
            return stopPointRef
        }

        var components: [String] = []
        if !latitude.isEmpty {
            components.append(latitude)
        }
        if !longitude.isEmpty {
            components.append(longitude)
        }
        if let recordedAt {
            components.append(String(Int(recordedAt.timeIntervalSince1970)))
        }
        if let validUntil {
            components.append(String(Int(validUntil.timeIntervalSince1970)))
        }

        if !components.isEmpty {
            return components.joined(separator: "_")
        }

        return UUID().uuidString
    }

    private static func decodeISO8601OrNil(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return iso8601.date(from: s)
    }

    private static func decodeDotNetDateOrNil(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return dotNetDate(from: s)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
        return f
    }()

    // Parses "/Date(1761640899000)/" into Date
    private static func dotNetDate(from string: String) -> Date? {
        // Extract the milliseconds number
        guard let start = string.firstIndex(of: "(") , let end = string.firstIndex(of: ")") else { return nil }
        let numString = String(string[string.index(after: start)..<end])
        if let ms = Double(numString) {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        return nil
    }
}

// MARK: - Networking
final class BusService {
    static let shared = BusService()
    private init() {}

    // Endpoint as provided
    private let baseURL = URL(string: "https://portal.go-coach.co.uk/v5/widget/api/buses?region=&showBusesNotInService=false")!

    func fetchBuses() async throws -> [Bus] {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        // If the server enforces a Referer check, uncomment the following line
        req.setValue("https://portal.go-coach.co.uk/WidgetV5/BusTracker?guid=d434607b-a8ad-450a-a16c-98ede0e08af3&style=gocoach&showBusTimings=true&operators=GoCoach&region=&origin=&destination=", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // The payload is a top-level array
        let decoder = JSONDecoder()
        return try decoder.decode([Bus].self, from: data)
    }
}

// MARK: - ViewModel
@MainActor
final class BusesViewModel: ObservableObject {
    @Published var buses: [Bus] = []
    @Published var cameraPosition: MapCameraPosition = .automatic
    @Published var isLoading = false
    @Published var errorMessage: String = ""

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await BusService.shared.fetchBuses()
            self.buses = items
            updateCameraToFit(buses: items)
            self.errorMessage = ""
        } catch {
            self.errorMessage = error.localizedDescription
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
        // Padding
        let latPad = max((maxLat - minLat) * 0.2, 0.02)
        let lonPad = max((maxLon - minLon) * 0.2, 0.02)

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) + latPad, longitudeDelta: (maxLon - minLon) + lonPad)
        let region = MKCoordinateRegion(center: center, span: span)
        cameraPosition = .region(region)
    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var vm = BusesViewModel()
    @State private var isShowingList = false
    @State private var selectedRoutes: Set<String> = []
    @State private var occupancyFilter: OccupancyFilter = .all
    @State private var searchQuery: String = ""
    @State private var focusedBusID: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $vm.cameraPosition) {
                    ForEach(filteredBuses) { bus in
                        if let coord = bus.coordinate {
                            Annotation(bus.title, coordinate: coord) {
                                BusAnnotationView(bus: bus)
                            }
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapPitchToggle()
                    MapUserLocationButton()
                }

                if vm.isLoading {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial, in: .capsule)
                        .padding()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Spacer()
                    if let bus = focusedBus {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "scope")
                                .font(.title3)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Showing selected bus")
                                    .font(.caption.smallCaps())
                                    .foregroundStyle(.secondary)

                                Text(bus.routeLabel ?? bus.title)
                                    .font(.headline)
                                Text(bus.destinationLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }

                    HStack {
                        Button {
                            isShowingList = true
                        } label: {
                            Label("Bus list & filters", systemImage: "list.bullet")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .accessibilityLabel("Show bus list and filters")

                        if hasActiveFilters {
                            Button {
                                resetFilters()
                            } label: {
                                Label(clearFiltersLabel, systemImage: "xmark.circle.fill")
                                    .font(.subheadline)
                            }
                            .padding(.leading, 8)
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Go Coach Buses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Open bus list")
                }
            }
            .task { await vm.refresh() }
            .alert("Error", isPresented: Binding(get: { !vm.errorMessage.isEmpty }, set: { newValue in
                if !newValue {
                    vm.errorMessage = ""
                }
            })) {
                Button("OK", role: .cancel) { vm.errorMessage = "" }
            } message: {
                Text(vm.errorMessage.isEmpty ? "Unknown error" : vm.errorMessage)
            }
            .sheet(isPresented: $isShowingList) {
                BusListSheet(
                    buses: filteredBuses,
                    allRoutes: sortedRoutes,
                    selectedRoutes: $selectedRoutes,
                    occupancyFilter: $occupancyFilter,
                    searchQuery: $searchQuery,
                    selectedBusID: focusedBusID,
                    isShowingSelectedBus: focusedBusID != nil,
                    onSelect: { bus in
                        focusedBusID = bus.id
                        vm.focus(on: bus)
                        isShowingList = false
                    },
                    onReset: resetFilters,
                    displayedBusCount: filteredBuses.count,
                    totalBusCount: vm.buses.count
                )
                .presentationDetents([.medium, .large])
            }
            .onChange(of: vm.buses) { newValue in
                let availableRoutes = Set(newValue.compactMap { $0.routeLabel })
                selectedRoutes = selectedRoutes.intersection(availableRoutes)
                ensureFocusedBusExists(in: newValue)
            }
        }
    }

    private var filteredBuses: [Bus] {
        if let focusedID = focusedBusID,
           let selectedBus = vm.buses.first(where: { $0.id == focusedID }) {
            return [selectedBus]
        }

        return vm.buses
            .filter { bus in
                matchesRouteFilter(bus: bus)
                && matchesOccupancyFilter(bus: bus)
                && matchesSearchQuery(bus: bus)
            }
            .sorted { lhs, rhs in
                let lhsRoute = lhs.routeLabel ?? lhs.title
                let rhsRoute = rhs.routeLabel ?? rhs.title
                if lhsRoute.caseInsensitiveCompare(rhsRoute) == .orderedSame {
                    return lhs.destinationLabel < rhs.destinationLabel
                }
                return lhsRoute.localizedCaseInsensitiveCompare(rhsRoute) == .orderedAscending
            }
    }

    private var sortedRoutes: [String] {
        let routes = vm.buses.compactMap { $0.routeLabel }
        return Array(Set(routes)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !selectedRoutes.isEmpty || occupancyFilter != .all || !searchQuery.isEmpty || focusedBusID != nil
    }

    private var clearFiltersLabel: String {
        focusedBusID != nil ? "Show all" : "Clear"
    }

    private var focusedBus: Bus? {
        guard let focusedBusID else { return nil }
        return vm.buses.first(where: { $0.id == focusedBusID })
    }

    private func resetFilters() {
        selectedRoutes.removeAll()
        occupancyFilter = .all
        searchQuery = ""
        focusedBusID = nil
    }

    private func matchesRouteFilter(bus: Bus) -> Bool {
        guard !selectedRoutes.isEmpty else { return true }
        guard let route = bus.routeLabel else { return false }
        return selectedRoutes.contains(route)
    }

    private func matchesOccupancyFilter(bus: Bus) -> Bool {
        switch occupancyFilter {
        case .all:
            return true
        case .manySeats:
            return bus.occupancyLevel == .plenty
        case .fewSeats:
            return bus.occupancyLevel == .limited
        case .full:
            return bus.occupancyLevel == .full
        case .unknown:
            return bus.occupancyLevel == .unknown
        }
    }

    private func matchesSearchQuery(bus: Bus) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let lowerQuery = query.lowercased()
        let haystack = [bus.title, bus.destinationLabel, bus.routeLabel ?? ""]
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(lowerQuery)
    }

    private func ensureFocusedBusExists(in buses: [Bus]) {
        guard let focusedBusID else { return }
        if !buses.contains(where: { $0.id == focusedBusID }) {
            focusedBusID = nil
        }
    }
}

private struct BusAnnotationView: View {
    let bus: Bus

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "bus.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                    }

                if let badge = bus.lineBadgeText {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.gradient, in: Capsule())
                        .offset(x: 14, y: -14)
                }
            }

            Circle()
                .fill(.primary)
                .frame(width: 6, height: 6)
                .opacity(0.4)
        }
        .shadow(radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bus.title)
        .accessibilityHint(bus.subtitle)
    }
}

private enum BusOccupancyLevel: String {
    case unknown
    case plenty
    case limited
    case full
}

private enum OccupancyFilter: String, CaseIterable, Identifiable {
    case all
    case manySeats
    case fewSeats
    case full
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All occupancy"
        case .manySeats:
            return "Many seats"
        case .fewSeats:
            return "Few seats"
        case .full:
            return "Full"
        case .unknown:
            return "Unknown"
        }
    }
}

private struct BusListSheet: View {
    let buses: [Bus]
    let allRoutes: [String]
    @Binding var selectedRoutes: Set<String>
    @Binding var occupancyFilter: OccupancyFilter
    @Binding var searchQuery: String
    let selectedBusID: String?
    let isShowingSelectedBus: Bool
    let onSelect: (Bus) -> Void
    let onReset: () -> Void
    let displayedBusCount: Int
    let totalBusCount: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !allRoutes.isEmpty {
                    Section("Routes") {
                        ForEach(allRoutes, id: \.self) { route in
                            MultipleSelectionRow(title: route, isSelected: selectedRoutes.contains(route)) {
                                toggleRoute(route)
                            }
                        }
                    }
                }

                Section("Occupancy") {
                    Picker("Occupancy", selection: $occupancyFilter) {
                        ForEach(OccupancyFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Search") {
                    TextField("Search route or destination", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Buses (\(displayedBusCount)/\(totalBusCount))")) {
                    if buses.isEmpty {
                        ContentUnavailableView("No buses match your filters", systemImage: "magnifyingglass")
                    } else {
                        ForEach(buses) { bus in
                            Button {
                                onSelect(bus)
                            } label: {
                                BusListRow(bus: bus, isSelected: bus.id == selectedBusID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Bus list")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasActiveFilters {
                        Button("Clear filters") { onReset() }
                    }
                }
            }
        }
    }

    private var hasActiveFilters: Bool {
        !selectedRoutes.isEmpty || occupancyFilter != .all || !searchQuery.isEmpty || isShowingSelectedBus
    }

    private func toggleRoute(_ route: String) {
        if selectedRoutes.contains(route) {
            selectedRoutes.remove(route)
        } else {
            selectedRoutes.insert(route)
        }
    }
}

private struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct BusListRow: View {
    let bus: Bus
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSelected {
                Label("Showing on map", systemImage: "scope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            HStack {
                Image(systemName: "bus")
                Text(bus.routeLabel ?? bus.title)
                    .font(.headline)
                Spacer()
                if let badge = bus.lineBadgeText {
                    Text(badge)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            Text(bus.destinationLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(bus.occupancyDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
    }
}
