import Foundation

final class BusService {
    static let shared = BusService()
    private init() {}

    private let baseURL = URL(string: "https://portal.go-coach.co.uk/v5/widget/api/buses?region=&showBusesNotInService=false")!
    private let vehicleBaseURL = URL(string: "https://portal.go-coach.co.uk/api/vehicle/")!

    func fetchBuses() async throws -> [Bus] {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.setValue(
            "https://portal.go-coach.co.uk/WidgetV5/BusTracker?guid=d434607b-a8ad-450a-a16c-98ede0e08af3&style=gocoach&showBusTimings=true&operators=GoCoach&region=&origin=&destination=",
            forHTTPHeaderField: "Referer"
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([Bus].self, from: data)
    }

    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus? {
        let url = vehicleBaseURL.appending(path: journeyCode)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let vehicle = try decoder.decode(VehicleDetails.self, from: data)
        return vehicle.timingStatus
    }
}
