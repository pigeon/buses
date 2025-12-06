import XCTest
@testable import buses

@MainActor
final class BusesViewModelTests: XCTestCase {
    func testRefreshUsesMockService() async throws {
        let mock = MockBusService()
        let bus = try makeBus(overrides: ["VehicleRef": "Mocked-1"])
        mock.busesResult = [bus]
        let viewModel = BusesViewModel(service: mock)

        await viewModel.refresh(shouldUpdateCamera: false)

        XCTAssertEqual(viewModel.buses, [bus])
        XCTAssertEqual(mock.fetchBusesCallCount, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFetchTimingStatusUsesMockService() async throws {
        let mock = MockBusService()
        let bus = try makeBus(overrides: ["JourneyCode": "JC123"])
        let expectedStatus = TimingStatus(minutes: 5, status: "On time")
        mock.timingStatusResult = expectedStatus
        let viewModel = BusesViewModel(service: mock)

        await viewModel.fetchTimingStatus(for: bus)

        XCTAssertEqual(mock.fetchTimingStatusCallCount, 1)
        XCTAssertEqual(viewModel.timingStatus(for: bus.id), expectedStatus)
    }
}

private final class MockBusService: BusServiceProtocol {
    var busesResult: [Bus] = []
    var timingStatusResult: TimingStatus?
    private(set) var fetchBusesCallCount = 0
    private(set) var fetchTimingStatusCallCount = 0

    func fetchBuses() async throws -> [Bus] {
        fetchBusesCallCount += 1
        return busesResult
    }

    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus? {
        fetchTimingStatusCallCount += 1
        return timingStatusResult
    }
}
