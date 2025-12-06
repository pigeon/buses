import Foundation

struct TimingStatus: Decodable, Equatable {
    let minutes: Int?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case minutes = "Minutes"
        case status = "Status"
    }

    var description: String {
        guard let status else { return "Timing: Unknown" }
        switch status {
        case 2:
            let delay = minutes ?? 0
            return "Timing: Late by \(delay) min\(delay == 1 ? "" : "s")"
        case 1:
            return "Timing: Early"
        case 0:
            return "Timing: On time"
        default:
            return "Timing: Status \(status)"
        }
    }
}

struct VehicleDetails: Decodable {
    let timingStatus: TimingStatus?

    enum CodingKeys: String, CodingKey {
        case timingStatus = "TimingStatus"
    }
}
