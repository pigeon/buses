import XCTest
@testable import buses

final class BusTests: XCTestCase {
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
        XCTAssertEqual(bus.coordinate!.latitude, 52.1234, accuracy: 0.0001)
        XCTAssertEqual(bus.coordinate!.longitude, -0.1234, accuracy: 0.0001)
    }

    func testStableIdentifierIsDeterministicWithoutSourceIDs() throws {
        let overrides: [String: Any] = [
            "VehicleRef": NSNull(),
            "LineRef": NSNull(),
            "PublishedLineName": NSNull(),
            "JourneyCode": NSNull(),
            "TicketMachineServiceCode": NSNull(),
            "BlockRef": NSNull(),
            "StopPointRef": NSNull(),
            "Latitude": "52.0000",
            "Longitude": "0.1000",
            "RecordedAtTime": "2024-01-01T00:00:00Z",
            "ValidUntilTime": "2024-01-01T00:05:00Z"
        ]

        let bus1 = try makeBus(overrides: overrides)
        let bus2 = try makeBus(overrides: overrides)

        XCTAssertEqual(bus1.id, bus2.id)

        let changedLocation = try makeBus(overrides: overrides.merging(["Latitude": "52.0001"]) { $1 })
        XCTAssertNotEqual(bus1.id, changedLocation.id)
    }
}
