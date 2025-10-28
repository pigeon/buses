# Bus Tracker UI Wireframes

These wireframes illustrate potential layouts for the refresh button, location button, and list/filter controls.

## 1. Default Map View with Primary Controls

```
┌────────────────────────────────────────┐
│  Map Title                 ⟳ Refresh   │
├────────────────────────────────────────┤
│                                        │
│          [ Map canvas with bus         │
│            markers + camera ]          │
│                                        │
│                                        │
│                              ⦿         │
│                           (Location)   │
│                                        │
│                                        │
│                                        │
│  ⌄ Open List                            │
└────────────────────────────────────────┘
```

* **Refresh button:** trailing navigation bar item with the familiar `arrow.clockwise` icon.
* **Location button:** floats above the bottom trailing corner, grouped with the native map control cluster.
* **List handle:** a subtle bottom sheet grabber inviting the user to drag up for the list & filters.

## 2. Bus List Drawer Expanded with Filters

```
┌────────────────────────────────────────┐
│  Map Title                 ⟳ Refresh   │
├────────────────────────────────────────┤
│         Map canvas remains visible     │
│ ─────────────────────────────────────  │
│ │ 🚍  Route 300  ▶︎  Swanley           │
│ │ Occupancy: Many seats                │
│ │                                      │
│ │ 🚍  Route 2    ▶︎  Bluewater         │
│ │ Occupancy: Few seats                 │
│ │                                      │
│ │ [Filter chips: Route ▾  Occupancy ▾] │
│ ─────────────────────────────────────  │
└────────────────────────────────────────┘
```

* **List sheet:** slides up from the bottom to reveal a scrollable list of buses.
* **Filter chips:** sit at the top of the sheet for quick narrowing by route, destination, or occupancy.
* **Map context:** remains visible above the sheet so users keep spatial awareness.

## 3. Filter-Only Quick Access Panel

```
┌────────────────────────────────────────┐
│  Map Title                 ⟳ Refresh   │
├────────────────────────────────────────┤
│                                        │
│   (Map canvas)                         │
│                                        │
│                                        │
│                                        │
│          ◉ Location    ☰ Filters       │
│                                        │
│                                        │
└────────────────────────────────────────┘
```

* **Location button:** larger circular button anchored near the lower trailing corner.
* **Filters button:** secondary floating button that opens a dedicated filter modal when tapped.
* **Gesture balance:** spacing keeps both buttons reachable without covering critical map content.

### Usage Notes

* Use system-provided `MapUserLocationButton` and `MapPitchToggle` to maintain platform consistency.
* The sheet-based list view can be driven by a `BottomSheet` or `sheet` modifier with a custom detent for half-height presentation.
* Highlight the active filters in the map annotations (e.g., dim filtered-out buses) to reinforce the connection between the sheet and map.
