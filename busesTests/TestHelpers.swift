import Foundation
@testable import buses

func makeBus(
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
