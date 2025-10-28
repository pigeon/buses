import Foundation
import MapKit

struct Bus: Decodable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case routeDescription = "RouteDescription"
        case destinationStopName = "DestinationStopName"
        case destinationStopLocality = "DestinationStopLocality"
        case destinationStopFullName = "DestinationStopFullName"
        case lastUpdated = "LastUpdated"
        case occupancy = "Occupancy"
        case departureTime = "DepartureTime"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case recordedAtTime = "RecordedAtTime"
        case validUntilTime = "ValidUntilTime"
        case lineRef = "LineRef"
        case directionRef = "DirectionRef"
        case publishedLineName = "PublishedLineName"
        case operatorRef = "OperatorRef"
        case bearing = "Bearing"
        case blockRef = "BlockRef"
        case ticketMachineServiceCode = "TicketMachineServiceCode"
        case journeyCode = "JourneyCode"
        case dbCreated = "DbCreated"
        case dataSetId = "DataSetId"
        case destinationRef = "DestinationRef"
        case nextStopName = "NextStopName"
        case nextStopLocality = "NextStopLocality"
        case nextStopFullName = "NextStopFullName"
        case stopPointRef = "StopPointRef"
        case currentStopName = "CurrentStopName"
        case currentStopLocality = "CurrentStopLocality"
        case currentStopFullName = "CurrentStopFullName"
        case vehicleAtStop = "VehicleAtStop"
        case visitNumber = "VisitNumber"
        case vehicleRef = "VehicleRef"
        case destination = "Destination"
        case timingStatus = "TimingStatus"
    }

    struct Occupancy: Decodable, Equatable {
        let seatedCapacity: Int?
        let seatedOccupancy: Int?
        let wheelchairCapacity: Int?
        let wheelchairOccupancy: Int?
        let status: Int?

        enum CodingKeys: String, CodingKey {
            case seatedCapacity = "SeatedCapacity"
            case seatedOccupancy = "SeatedOccupancy"
            case wheelchairCapacity = "WheelchairCapacity"
            case wheelchairOccupancy = "WheelchairOccupancy"
            case status = "Status"
        }
    }

    // Raw fields
    let routeDescription: String?
    let destinationStopName: String?
    let destinationStopLocality: String?
    let destinationStopFullName: String?
    let lastUpdated: Date?
    let occupancy: Occupancy?
    let departureTimeISO: Date?
    let latitudeString: String
    let longitudeString: String
    let recordedAtTimeISO: Date?
    let validUntilTimeISO: Date?
    let lineRef: String?
    let directionRef: String?
    let publishedLineName: String?
    let operatorRef: String?
    let bearing: String?
    let blockRef: String?
    let ticketMachineServiceCode: String?
    let journeyCode: String?
    let dbCreated: Date?
    let dataSetId: Int?
    let destinationRef: String?
    let nextStopName: String?
    let nextStopLocality: String?
    let nextStopFullName: String?
    let stopPointRef: String?
    let currentStopName: String?
    let currentStopLocality: String?
    let currentStopFullName: String?
    let vehicleAtStop: Bool?
    let visitNumber: String?
    let vehicleRef: String?
    let destination: String?
    let timingStatus: String?
    private let stableIdentifier: String

    var id: String { stableIdentifier }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitudeString), let lon = Double(longitudeString) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var title: String {
        if let line = publishedLineName ?? lineRef { return line }
        return vehicleRef ?? "Bus"
    }

    var subtitle: String {
        if let dest = destinationStopFullName ?? destinationStopName { return dest }
        return currentStopFullName ?? currentStopName ?? ""
    }

    var lineBadgeText: String? {
        guard let name = publishedLineName ?? lineRef else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(4))
    }

    var routeLabel: String? {
        let trimmedName = publishedLineName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = trimmedName, !name.isEmpty { return name }
        let trimmedRef = lineRef?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ref = trimmedRef, !ref.isEmpty { return ref }
        return nil
    }

    var destinationLabel: String {
        subtitle.isEmpty ? (destination ?? "") : subtitle
    }

    var occupancyDescription: String {
        switch occupancyLevel {
        case .unknown:
            return "Occupancy: Unknown"
        case .plenty:
            return "Occupancy: Many seats"
        case .limited:
            return "Occupancy: Few seats"
        case .full:
            return "Occupancy: Full"
        }
    }

    var occupancyLevel: BusOccupancyLevel {
        guard let capacity = occupancy?.seatedCapacity, capacity > 0,
              let seated = occupancy?.seatedOccupancy else {
            return .unknown
        }
        let ratio = Double(seated) / Double(capacity)
        if ratio < 0.4 { return .plenty }
        if ratio < 0.85 { return .limited }
        return .full
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routeDescription = try c.decodeIfPresent(String.self, forKey: .routeDescription)
        destinationStopName = try c.decodeIfPresent(String.self, forKey: .destinationStopName)
        destinationStopLocality = try c.decodeIfPresent(String.self, forKey: .destinationStopLocality)
        destinationStopFullName = try c.decodeIfPresent(String.self, forKey: .destinationStopFullName)
        occupancy = try c.decodeIfPresent(Occupancy.self, forKey: .occupancy)

        lastUpdated = try Bus.decodeDotNetDateOrNil(from: c, key: .lastUpdated)
        dbCreated = try Bus.decodeDotNetDateOrNil(from: c, key: .dbCreated)
        departureTimeISO = try Bus.decodeISO8601OrNil(from: c, key: .departureTime)
        recordedAtTimeISO = try Bus.decodeISO8601OrNil(from: c, key: .recordedAtTime)
        validUntilTimeISO = try Bus.decodeISO8601OrNil(from: c, key: .validUntilTime)

        latitudeString = try c.decode(String.self, forKey: .latitude)
        longitudeString = try c.decode(String.self, forKey: .longitude)
        lineRef = try c.decodeIfPresent(String.self, forKey: .lineRef)
        directionRef = try c.decodeIfPresent(String.self, forKey: .directionRef)
        publishedLineName = try c.decodeIfPresent(String.self, forKey: .publishedLineName)
        operatorRef = try c.decodeIfPresent(String.self, forKey: .operatorRef)
        bearing = try c.decodeIfPresent(String.self, forKey: .bearing)
        blockRef = try c.decodeIfPresent(String.self, forKey: .blockRef)
        ticketMachineServiceCode = try c.decodeIfPresent(String.self, forKey: .ticketMachineServiceCode)
        journeyCode = try c.decodeIfPresent(String.self, forKey: .journeyCode)
        dataSetId = try c.decodeIfPresent(Int.self, forKey: .dataSetId)
        destinationRef = try c.decodeIfPresent(String.self, forKey: .destinationRef)
        nextStopName = try c.decodeIfPresent(String.self, forKey: .nextStopName)
        nextStopLocality = try c.decodeIfPresent(String.self, forKey: .nextStopLocality)
        nextStopFullName = try c.decodeIfPresent(String.self, forKey: .nextStopFullName)
        stopPointRef = try c.decodeIfPresent(String.self, forKey: .stopPointRef)
        currentStopName = try c.decodeIfPresent(String.self, forKey: .currentStopName)
        currentStopLocality = try c.decodeIfPresent(String.self, forKey: .currentStopLocality)
        currentStopFullName = try c.decodeIfPresent(String.self, forKey: .currentStopFullName)
        vehicleAtStop = try c.decodeIfPresent(Bool.self, forKey: .vehicleAtStop)
        visitNumber = try c.decodeIfPresent(String.self, forKey: .visitNumber)
        vehicleRef = try c.decodeIfPresent(String.self, forKey: .vehicleRef)
        destination = try c.decodeIfPresent(String.self, forKey: .destination)
        timingStatus = try c.decodeIfPresent(String.self, forKey: .timingStatus)

        stableIdentifier = Bus.makeStableIdentifier(
            vehicleRef: vehicleRef,
            lineRef: lineRef,
            journeyCode: journeyCode,
            ticketMachineServiceCode: ticketMachineServiceCode,
            blockRef: blockRef,
            stopPointRef: stopPointRef,
            latitude: latitudeString,
            longitude: longitudeString,
            recordedAt: recordedAtTimeISO,
            validUntil: validUntilTimeISO
        )
    }

    private static func makeStableIdentifier(
        vehicleRef: String?,
        lineRef: String?,
        journeyCode: String?,
        ticketMachineServiceCode: String?,
        blockRef: String?,
        stopPointRef: String?,
        latitude: String,
        longitude: String,
        recordedAt: Date?,
        validUntil: Date?
    ) -> String {
        if let vehicleRef, let lineRef {
            return "\(vehicleRef)_\(lineRef)"
        }
        if let vehicleRef {
            return vehicleRef
        }
        if let journeyCode, !journeyCode.isEmpty {
            return journeyCode
        }
        if let ticketMachineServiceCode, !ticketMachineServiceCode.isEmpty {
            return ticketMachineServiceCode
        }
        if let blockRef, !blockRef.isEmpty {
            return blockRef
        }
        if let stopPointRef, !stopPointRef.isEmpty {
            return stopPointRef
        }

        var components: [String] = []
        if !latitude.isEmpty {
            components.append(latitude)
        }
        if !longitude.isEmpty {
            components.append(longitude)
        }
        if let recordedAt {
            components.append(String(Int(recordedAt.timeIntervalSince1970)))
        }
        if let validUntil {
            components.append(String(Int(validUntil.timeIntervalSince1970)))
        }

        if !components.isEmpty {
            return components.joined(separator: "_")
        }

        return UUID().uuidString
    }

    private static func decodeISO8601OrNil(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return iso8601.date(from: s)
    }

    private static func decodeDotNetDateOrNil(from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return dotNetDate(from: s)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTime, .withColonSeparatorInTimeZone]
        return f
    }()

    private static func dotNetDate(from string: String) -> Date? {
        guard let start = string.firstIndex(of: "("), let end = string.firstIndex(of: ")") else { return nil }
        let numString = String(string[string.index(after: start)..<end])
        if let ms = Double(numString) {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        return nil
    }
}

enum BusOccupancyLevel: String {
    case unknown
    case plenty
    case limited
    case full
}
