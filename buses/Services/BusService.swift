import Foundation
import os.log

protocol BusServiceProtocol {
    func fetchBuses() async throws -> [Bus]
    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus?
}

final class BusService: BusServiceProtocol {
    static let shared = BusService()
    private init() {}

    private let logger = Logger(subsystem: "com.gocoach.buses", category: "network")
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

        let (data, http) = try await performRequest(req, requestLabel: "fetchBuses")
        guard (200..<300).contains(http.statusCode) else {
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

        if let url = req.url,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {

            components.queryItems = [
                URLQueryItem(name: "includeLastCleanedLog", value: "true"),
                URLQueryItem(name: "includeTimings", value: "true"),
                URLQueryItem(name: "includeLiveOccupancy", value: "true")
            ]

            // Update the request with the new URL
            req.url = components.url
        }

        let (data, http) = try await performRequest(req, requestLabel: "fetchTimingStatus")
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        let vehicle = try decoder.decode(VehicleDetails.self, from: data)
        return vehicle.timingStatus
    }

    private func performRequest(
        _ request: URLRequest,
        requestLabel: String
    ) async throws -> (Data, HTTPURLResponse) {
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<missing URL>"
        let requestHeaders = formatHeaders(request.allHTTPHeaderFields ?? [:])
        let requestBody = prettyPrintedPayload(from: request.httpBody) ?? "<empty>"

        logger.debug("[\(requestLabel, privacy: .public)] -> \(method, privacy: .public) \(urlString, privacy: .public)")
        logger.debug("[\(requestLabel, privacy: .public)] request headers: \(requestHeaders, privacy: .public)")
        logger.debug("[\(requestLabel, privacy: .public)] request body: \(requestBody, privacy: .public)")

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

            guard let http = response as? HTTPURLResponse else {
                logger.error("[\(requestLabel, privacy: .public)] <- non-HTTP response after \(elapsedMs, privacy: .public) ms")
                throw URLError(.badServerResponse)
            }

            let responseHeaders = formatHeaders(http.allHeaderFields)
            let responseBody = prettyPrintedPayload(from: data) ?? "<non-UTF8 \(data.count) bytes>"
            logger.debug(
                "[\(requestLabel, privacy: .public)] <- status \(http.statusCode, privacy: .public) in \(elapsedMs, privacy: .public) ms"
            )
            logger.debug("[\(requestLabel, privacy: .public)] response headers: \(responseHeaders, privacy: .public)")
            logger.debug("[\(requestLabel, privacy: .public)] response body: \(responseBody, privacy: .public)")

            return (data, http)
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            logger.error(
                "[\(requestLabel, privacy: .public)] request failed after \(elapsedMs, privacy: .public) ms: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    private func prettyPrintedPayload(from data: Data?) -> String? {
        guard let data else { return nil }
        guard !data.isEmpty else { return "" }

        if let object = try? JSONSerialization.jsonObject(with: data, options: []),
           let formattedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
           let json = String(data: formattedData, encoding: .utf8) {
            return json
        }

        return String(data: data, encoding: .utf8)
    }

    private func formatHeaders(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "<none>" }
        return headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func formatHeaders(_ headers: [AnyHashable: Any]) -> String {
        guard !headers.isEmpty else { return "<none>" }

        return headers
            .map { (key: String(describing: $0.key), value: String(describing: $0.value)) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}
