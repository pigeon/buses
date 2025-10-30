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
                Map(position: $viewModel.cameraPosition) {
                    ForEach(filteredBuses) { bus in
                        if let coordinate = bus.coordinate {
                            Annotation(bus.title, coordinate: coordinate) {
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
                        }
                        .padding(14)
                        .background(
                            .thinMaterial,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .padding(.horizontal)
                    }

                    HStack {
                        if hasActiveFilters {
                            Button { resetFilters() } label: {
                                Label(clearFiltersLabel, systemImage: "xmark.circle.fill")
                                    .font(.subheadline)
                            }
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
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button { isShowingList = true } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Open bus list")
                }
            }
            .task { await viewModel.refresh() }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { newValue in
                        if !newValue {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
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
                        viewModel.focus(on: bus)
                        isShowingList = false
                    },
                    onReset: resetFilters,
                    displayedBusCount: filteredBuses.count,
                    totalBusCount: viewModel.buses.count
                )
                .presentationDetents([.medium, .large])
            }
            .onChange(of: viewModel.buses) { newValue in
                let availableRoutes = Set(newValue.compactMap { $0.routeLabel })
                selectedRoutes = selectedRoutes.intersection(availableRoutes)
                ensureFocusedBusExists(in: newValue)
                updateCameraForFilters()
            }
            .onChange(of: selectedRoutes) { _ in
                updateCameraForFilters()
            }
            .onChange(of: searchQuery) { _ in
                updateCameraForFilters()
            }
            .onChange(of: focusedBusID) { newValue in
                if newValue == nil {
                    updateCameraForFilters()
                }
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
        updateCameraForFilters()
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

    private func updateCameraForFilters() {
        guard focusedBusID == nil else { return }
        viewModel.fitToBuses(filteredBuses)
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
        !selectedRoutes.isEmpty || !searchQuery.isEmpty || isShowingSelectedBus
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

#Preview {
    ContentView()
}
