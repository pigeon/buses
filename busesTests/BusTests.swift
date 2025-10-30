import XCTest
@testable import buses

final class BusTests: XCTestCase {
    private func makeBus(
        occupancy: [String: Any]? = nil,
        overrides: [String: Any] = [:]
    ) throws -> Bus {
        var payload: [String: Any] = [
            "Latitude": "52.1234",
            "Longitude": "-0.1234",
            "VehicleRef": "Vehicle-42",
            "LineRef": "Line 123",
            "PublishedLineName": "  123A  ",
            "DestinationStopFullName": "Central Station"
        ]

        if let occupancy {
            payload["Occupancy"] = occupancy
        }

        overrides.forEach { payload[$0.key] = $0.value }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let decoder = JSONDecoder()
        return try decoder.decode(Bus.self, from: data)
    }

    func testOccupancyLevelPlenty() throws {
        let occupancy = [
            "SeatedCapacity": 40,
            "SeatedOccupancy": 10
        ]
        let bus = try makeBus(occupancy: occupancy)

        XCTAssertEqual(bus.occupancyLevel, .plenty)
        XCTAssertEqual(bus.occupancyDescription, "Occupancy: Many seats")
    }

    func testOccupancyLevelLimited() throws {
        let occupancy = [
            "SeatedCapacity": 40,
            "SeatedOccupancy": 20
        ]
        let bus = try makeBus(occupancy: occupancy)

        XCTAssertEqual(bus.occupancyLevel, .limited)
        XCTAssertEqual(bus.occupancyDescription, "Occupancy: Few seats")
    }

    func testOccupancyLevelFull() throws {
        let occupancy = [
            "SeatedCapacity": 40,
            "SeatedOccupancy": 38
        ]
        let bus = try makeBus(occupancy: occupancy)

        XCTAssertEqual(bus.occupancyLevel, .full)
        XCTAssertEqual(bus.occupancyDescription, "Occupancy: Full")
    }

    func testLineBadgeTrimsWhitespace() throws {
        let bus = try makeBus()

        XCTAssertEqual(bus.lineBadgeText, "123A")
        XCTAssertEqual(bus.routeLabel, "123A")
    }

    func testDestinationLabelFallsBackToDestination() throws {
        let bus = try makeBus(
            overrides: [
                "DestinationStopFullName": NSNull(),
                "DestinationStopName": NSNull(),
                "Destination": "Depot"
            ]
        )

        XCTAssertEqual(bus.subtitle, "")
        XCTAssertEqual(bus.destinationLabel, "Depot")
    }

    func testCoordinateIsComputedFromStringValues() throws {
        let bus = try makeBus()

        XCTAssertNotNil(bus.coordinate)
        XCTAssertEqual(bus.coordinate?.latitude, 52.1234, accuracy: 0.0001)
        XCTAssertEqual(bus.coordinate?.longitude, -0.1234, accuracy: 0.0001)
    }
}
