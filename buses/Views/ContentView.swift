import SwiftUI
import MapKit
import _MapKit_SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = BusesViewModel()
    @State private var isShowingList = false
    @State private var selectedRoutes: Set<String> = []
    @State private var searchQuery: String = ""
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer
                loadingIndicator
                overlayControls
            }
            .navigationTitle("Go Coach Buses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await viewModel.refresh(shouldUpdateCamera: shouldAllowCameraAutoUpdate)
                        }
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
            .task {
                await viewModel.refresh()
                startRefreshLoop()
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    startRefreshLoop()
                case .inactive, .background:
                    stopRefreshLoop()
                @unknown default:
                    break
                }
            }
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
                    selectedBusID: viewModel.focusedBusID,
                    isShowingSelectedBus: viewModel.focusedBusID != nil,
                    onSelect: { bus in
                        viewModel.focus(on: bus)
                        Task { await viewModel.fetchTimingStatus(for: bus) }
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
                viewModel.clearFocusIfMissing(in: newValue)
                updateCameraForFilters()
            }
            .onChange(of: selectedRoutes) { _ in
                viewModel.fitToBuses(filteredBuses)
                updateCameraForFilters(force: true)
            }
            .onChange(of: searchQuery) { _ in
                viewModel.fitToBuses(filteredBuses)
                updateCameraForFilters(force: true)
            }
            .onChange(of: viewModel.focusedBusID) { newValue in
                if newValue == nil {
                    updateCameraForFilters(force: true)
                }
            }
        }
    }

    private var mapContent: some View {
        Map(
            position: $viewModel.cameraPosition,
            selection: $viewModel.focusedBusID
        ) {
            ForEach(filteredBuses, id: \.id) { bus in
                if let coordinate = bus.coordinate {
                    Annotation(bus.title, coordinate: coordinate) {
                        BusAnnotationView(bus: bus)
                            .onTapGesture {
                                viewModel.focus(on: bus)
                                Task { await viewModel.fetchTimingStatus(for: bus) }
                            }
                    }
                    .tag(bus.id)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
            MapUserLocationButton()
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            freezeCameraForUserInteraction()
        })
        .simultaneousGesture(MagnificationGesture().onChanged { _ in
            freezeCameraForUserInteraction()
        })
        .simultaneousGesture(RotationGesture().onChanged { _ in
            freezeCameraForUserInteraction()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            freezeCameraForUserInteraction()
        })
    }

//    private var mapContent: some View {
//        Map(
//            position: $viewModel.cameraPosition,
//            selection: $viewModel.focusedBusID
//        ) {
//            ForEach(filteredBuses, id: \.id) { bus in
//                if let coordinate = bus.coordinate {
//                    Annotation(bus.title, coordinate: coordinate) {
//                        BusAnnotationView(bus: bus)
//                            .onTapGesture {
//                                viewModel.focusedBusID = bus.id
//                                Task { await viewModel.fetchTimingStatus(for: bus) }
//                            }
//                    }
//                    .tag(bus.id)
//                    .annotationTitles { _ in
//                        Text(bus.routeLabel ?? bus.title)
//                    }
//                    .annotationSubtitles { _ in
//                        VStack(alignment: .leading, spacing: 2) {
//                            Text(bus.destinationLabel)
//
//                            if let statusText = timingDescription(for: bus.id) {
//                                Text(statusText)
//                            }
//                        }
//                    }
//                }
//            }
//        }
//        .mapControls {
//            MapCompass()
//            MapScaleView()
//            MapPitchToggle()
//            MapUserLocationButton()
//        }
//        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
//            freezeCameraForUserInteraction()
//        })
//        .simultaneousGesture(MagnificationGesture().onChanged { _ in
//            freezeCameraForUserInteraction()
//        })
//        .simultaneousGesture(RotationGesture().onChanged { _ in
//            freezeCameraForUserInteraction()
//        })
//        .simultaneousGesture(TapGesture(count: 2).onEnded {
//            freezeCameraForUserInteraction()
//        })
//    }

    @ViewBuilder
    private var mapLayer: some View {
        mapContent
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding(8)
                .background(.ultraThinMaterial, in: .capsule)
                .padding()
        }
    }

    @ViewBuilder
    private var overlayControls: some View {
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

                        if let statusText = timingDescription(for: bus.id) {
                            Text(statusText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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

                if viewModel.cameraMode == .manual {
                    Button { recenterCamera() } label: {
                        Label("Recenter map", systemImage: "location.circle")
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

    private var filteredBuses: [Bus] {
        if let focusedID = viewModel.focusedBusID,
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
        !selectedRoutes.isEmpty || !searchQuery.isEmpty || viewModel.focusedBusID != nil
    }

    private var shouldAllowCameraAutoUpdate: Bool {
        viewModel.cameraMode == .follow && !hasActiveFilters
    }

    private var clearFiltersLabel: String {
        viewModel.focusedBusID != nil ? "Show all" : "Clear"
    }

    private var focusedBus: Bus? {
        guard let focusedBusID = viewModel.focusedBusID else { return nil }
        return viewModel.buses.first(where: { $0.id == focusedBusID })
    }

    private func timingDescription(for busID: Bus.ID) -> String? {
        guard let status = viewModel.timingStatus(for: busID) else { return nil }
        return status.lateDescription
    }

    private func resetFilters() {
        selectedRoutes.removeAll()
        searchQuery = ""
        viewModel.focusedBusID = nil
        recenterCamera()
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

    private var hasQueryOrRouteFilters: Bool {
        !selectedRoutes.isEmpty || !searchQuery.isEmpty
    }

    private func freezeCameraForUserInteraction() {
        viewModel.enterManualCameraMode()
    }

    private func recenterCamera() {
        viewModel.resetCamera(using: hasQueryOrRouteFilters ? filteredBuses : viewModel.buses)
    }

    private func updateCameraForFilters(force: Bool = false) {
        guard viewModel.focusedBusID == nil else { return }
        guard hasQueryOrRouteFilters else { return }
        guard force || viewModel.cameraMode == .follow else { return }

        viewModel.fitToBuses(filteredBuses)
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()

        guard scenePhase == .active else { return }

        refreshTask = Task {
            let thirtySeconds: UInt64 = 30_000_000_000

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: thirtySeconds)
                } catch {
                    break
                }

                let allowAutoUpdate = await MainActor.run { shouldAllowCameraAutoUpdate }
                await viewModel.refresh(shouldUpdateCamera: allowAutoUpdate)
            }
        }
    }

    private func stopRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

private struct BusListSheet: View {
    let buses: [Bus]
    let allRoutes: [String]
    @Binding var selectedRoutes: Set<String>
    @Binding var searchQuery: String
    let selectedBusID: Bus.ID?
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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
