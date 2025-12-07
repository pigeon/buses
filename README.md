# Go Coach Buses (iOS)

A SwiftUI app that displays live Go Coach bus locations on a map, lets riders filter or search for routes, and shows capacity/timing hints. The UI refreshes automatically so the map stays current while still allowing users to freeze or refocus the camera when they are inspecting a specific bus.

## Features
- **Live map** powered by MapKit annotations for every bus that reports coordinates.
- **Route & search filters** to narrow the visible buses and recenter the map to matching results.
- **Bus list sheet** with selection, quick badges, and a “show on map” affordance for any item.
- **Occupancy & timing hints** derived from the vehicle feed, including late-running messages.
- **Auto refresh** on launch and every 30 seconds, plus a manual refresh action.

## Project structure
```
├─ busesApp.swift           # App entry point
├─ Views/ContentView.swift  # Main UI (map, filters, bus list sheet)
├─ ViewModels/BusesViewModel.swift
│   └─ State management, camera logic, polling
├─ Services/BusService.swift
│   └─ Networking for buses and timing status
├─ Models/
│   ├─ Bus.swift            # Vehicle payload parsing & derived properties
│   └─ TimingStatus.swift   # Late status decoding
└─ busesTests/              # XCTests & helpers
```

## Architecture
The app follows an MVVM-style split:
- **View (SwiftUI):** `ContentView` renders the map, overlays, filters, and the list sheet. It reacts to `BusesViewModel` state, drives focus/filters, and coordinates camera behavior when the user interacts with the map.
- **ViewModel:** `BusesViewModel` owns the bus collection, error/loading flags, a MapKit camera position, and a cache of per-bus timing statuses. It refreshes data, recenters the map to fit results or a selection, and fetches timing status on demand.
- **Service:** `BusService` performs network calls against the Go Coach endpoints: the widget feed for buses and per-vehicle endpoints (with timing/occupancy flags). A protocol (`BusServiceProtocol`) enables mocking.
- **Models:** `Bus` and `TimingStatus` decode the API responses and expose derived properties such as coordinates, occupancy level/description, route labels, and stable identifiers for annotation selection.

## Data flow
1. `ContentView` launches and triggers `BusesViewModel.refresh()`, which loads buses from the widget API and fits the camera to available coordinates.
2. The map shows annotations for `filteredBuses`, derived from user-selected routes and search text. Selecting a bus focuses the map and kicks off `fetchTimingStatus` for late/occupancy hints.
3. A 30-second loop in `ContentView` keeps data fresh; users can also pull a manual refresh from the toolbar. Map gestures freeze auto-recentering until the user opts to recenter.

## Running the app
1. Open `buses.xcodeproj` in Xcode 15 (or later) on macOS.
2. Select an iOS 17+ simulator (or device) and build/run the **buses** scheme. The app loads live data from `portal.go-coach.co.uk`, so network access is required.

## Testing
Run the unit tests from Xcode or via the CLI. Example CLI invocation:
```
xcodebuild test \
  -scheme buses \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```
Tests cover bus decoding/derivations and view-model interactions with a mock service.
