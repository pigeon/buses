import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var viewModel = BusesViewModel()
    @State private var isShowingList = false
    @State private var selectedRoutes: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var focusedBusID: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(
                    coordinateRegion: $viewModel.cameraRegion,
                    interactionModes: .all,
                    showsUserLocation: false,
                    userTrackingMode: .none
                ) {
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

                if viewModel.isLoading {
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

                            Spacer()

                            Button(role: .cancel) {
                                focusedBusID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Button {
                            isShowingList.toggle()
                        } label: {
                            Label("Buses", systemImage: "bus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if hasActiveFilters {
                            Button(role: .destructive) {
                                resetFilters()
                            } label: {
                                Label(clearFiltersLabel, systemImage: "line.3.horizontal.decrease.circle")
                                    .labelStyle(.titleAndIcon)
                                    .font(.headline)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding()
            }
            .navigationTitle("Go Coach buses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
            }
            .task {
                await viewModel.refresh()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(isPresented: $isShowingList) {
                BusListSheet(
                    buses: filteredBuses,
                    allRoutes: sortedRoutes,
                    selectedRoutes: $selectedRoutes,
                    searchQuery: $searchQuery,
                    selectedBusID: focusedBusID,
                    isShowingSelectedBus: focusedBusID != nil,
                    onSelect: { bus in
                        focusedBusID = bus.id
                        isShowingList = false
                        viewModel.focus(on: bus)
                    },
                    onReset: {
                        resetFilters()
                        isShowingList = false
                    },
                    displayedBusCount: filteredBuses.count,
                    totalBusCount: viewModel.buses.count
                )
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: { error in
                Text(error)
            }
            .onChange(of: viewModel.buses) { newValue in
                let availableRoutes = Set(newValue.compactMap { $0.routeLabel })
                selectedRoutes = selectedRoutes.intersection(availableRoutes)
                ensureFocusedBusExists(in: newValue)
            }
        }
    }

    private var filteredBuses: [Bus] {
        if let focusedID = focusedBusID,
           let selectedBus = viewModel.buses.first(where: { $0.id == focusedID }) {
            return [selectedBus]
        }

        return viewModel.buses
            .filter { bus in
                matchesRouteFilter(bus: bus)
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
        let routes = viewModel.buses.compactMap { $0.routeLabel }
        return Array(Set(routes)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !selectedRoutes.isEmpty || !searchQuery.isEmpty || focusedBusID != nil
    }

    private var clearFiltersLabel: String {
        focusedBusID != nil ? "Show all" : "Clear"
    }

    private var focusedBus: Bus? {
        guard let focusedBusID else { return nil }
        return viewModel.buses.first(where: { $0.id == focusedBusID })
    }

    private func resetFilters() {
        selectedRoutes.removeAll()
        searchQuery = ""
        focusedBusID = nil
    }

    private func matchesRouteFilter(bus: Bus) -> Bool {
        guard !selectedRoutes.isEmpty else { return true }
        guard let route = bus.routeLabel else { return false }
        return selectedRoutes.contains(route)
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
        guard let currentFocusedID = focusedBusID else { return }
        if !buses.contains(where: { $0.id == currentFocusedID }) {
            focusedBusID = nil
        }
    }
}

private struct BusAnnotationView: View {
    let bus: Bus

    var body: some View {
        VStack(spacing: 4) {
            if let badge = bus.lineBadgeText {
                Text(badge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }

            Image(systemName: "bus.fill")
                .font(.title2)
                .padding(6)
                .background(.thinMaterial, in: Circle())
        }
    }
}

private struct BusListSheet: View {
    let buses: [Bus]
    let allRoutes: [String]
    @Binding var selectedRoutes: Set<String>
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
                                dismiss()
                            } label: {
                                BusRow(bus: bus, isFocused: bus.id == selectedBusID)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Buses")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isShowingSelectedBus ? "Show all" : "Clear") {
                        onReset()
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleRoute(_ route: String) {
        if selectedRoutes.contains(route) {
            selectedRoutes.remove(route)
        } else {
            selectedRoutes.insert(route)
        }
    }
}

private struct BusRow: View {
    let bus: Bus
    let isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFocused ? "scope" : "bus.fill")
                .font(.title2)
                .foregroundStyle(isFocused ? .tint : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bus.routeLabel ?? bus.title)
                        .font(.headline)
                    Spacer()
                    if let badge = bus.lineBadgeText {
                        Text(badge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.2), in: Capsule())
                    }
                }

                Text(bus.destinationLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(bus.occupancyDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
