import Foundation

struct TimingStatus: Decodable, Equatable {
    let minutes: Int?
    let status: Int?

    enum CodingKeys: String, CodingKey {
        case minutes = "Minutes"
        case status = "Status"
    }

    var lateDescription: String? {
        guard status == 2, let minutes else { return nil }
        return "Timing: Late by \(minutes) min\(minutes == 1 ? "" : "s")"
    }
}

struct VehicleDetails: Decodable {
    let timingStatus: TimingStatus?

    enum CodingKeys: String, CodingKey {
        case timingStatus = "TimingStatus"
    }
}
