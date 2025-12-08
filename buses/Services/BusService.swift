import Foundation
import os

protocol BusServiceProtocol {
    func fetchBuses() async throws -> [Bus]
    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus?
}

struct BusServiceConfiguration {
    let busesURL: URL
    let vehicleBaseURL: URL
    let defaultHeaders: [String: String]

    static let production = BusServiceConfiguration(
        busesURL: URL(string: "https://portal.go-coach.co.uk/v5/widget/api/buses?region=&showBusesNotInService=false")!,
        vehicleBaseURL: URL(string: "https://portal.go-coach.co.uk/api/vehicle/")!,
        defaultHeaders: [
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Referer": "https://portal.go-coach.co.uk/WidgetV5/BusTracker?guid=d434607b-a8ad-450a-a16c-98ede0e08af3&style=gocoach&showBusTimings=true&operators=GoCoach&region=&origin=&destination="
        ]
    )
}

struct RequestRetryPolicy {
    let maxAttempts: Int
    let delay: TimeInterval

    static let `default` = RequestRetryPolicy(maxAttempts: 3, delay: 0.5)
}

final class BusService: BusServiceProtocol {
    static let shared = BusService()

    private let configuration: BusServiceConfiguration
    private let session: URLSession
    private let retryPolicy: RequestRetryPolicy
    private let logger = Logger(subsystem: "com.gocoach.buses", category: "BusService")

    init(
        configuration: BusServiceConfiguration = .production,
        session: URLSession = .shared,
        retryPolicy: RequestRetryPolicy = .default
    ) {
        self.configuration = configuration
        self.session = session
        self.retryPolicy = retryPolicy
    }

    func fetchBuses() async throws -> [Bus] {
        var req = URLRequest(url: configuration.busesURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        configuration.defaultHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await performWithRetry(request: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([Bus].self, from: data)
    }

    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus? {
        let url = configuration.vehicleBaseURL.appending(path: journeyCode)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        configuration.defaultHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        if let url = req.url,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {

            components.queryItems = [
                URLQueryItem(name: "includeLastCleanedLog", value: "true"),
                URLQueryItem(name: "includeTimings", value: "true"),
                URLQueryItem(name: "includeLiveOccupancy", value: "true")
            ]

            req.url = components.url
        }

        let (data, response) = try await performWithRetry(request: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        logger.debug("Fetched timing status for journey code \(journeyCode, privacy: .public) with status code \(http.statusCode)")

        let decoder = JSONDecoder()
        let vehicle = try decoder.decode(VehicleDetails.self, from: data)
        return vehicle.timingStatus
    }

    private func performWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
        var attempts = 0
        var currentError: Error?

        while attempts < retryPolicy.maxAttempts {
            do {
                return try await session.data(for: request)
            } catch {
                currentError = error
                attempts += 1
                if attempts >= retryPolicy.maxAttempts { break }
                try await Task.sleep(nanoseconds: UInt64(retryPolicy.delay * 1_000_000_000))
            }
        }

        throw currentError ?? URLError(.unknown)
    }
}
