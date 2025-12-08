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
        let expectedStatus = TimingStatus(minutes: 5, status: 0)
        mock.timingStatusResult = expectedStatus
        let viewModel = BusesViewModel(service: mock)

        await viewModel.fetchTimingStatus(for: bus)

        XCTAssertEqual(mock.fetchTimingStatusCallCount, 1)
        XCTAssertEqual(viewModel.timingStatus(for: bus.id), expectedStatus)
    }

    func testTimingStatusCacheExpiresAfterTTL() async throws {
        let mock = MockBusService()
        let bus = try makeBus(overrides: ["JourneyCode": "JC123"])
        let expectedStatus = TimingStatus(minutes: 5, status: 0)
        mock.timingStatusResult = expectedStatus

        var now = Date()
        let viewModel = BusesViewModel(
            service: mock,
            timingStatusTTL: 10,
            dateProvider: { now }
        )

        await viewModel.fetchTimingStatus(for: bus)

        XCTAssertEqual(viewModel.timingStatus(for: bus.id), expectedStatus)
        XCTAssertEqual(mock.fetchTimingStatusCallCount, 1)

        now = now.addingTimeInterval(9)
        XCTAssertEqual(viewModel.timingStatus(for: bus.id), expectedStatus)

        now = now.addingTimeInterval(2)
        XCTAssertNil(viewModel.timingStatus(for: bus.id))
    }

    func testFetchTimingStatusRefetchesWhenStale() async throws {
        let mock = MockBusService()
        let bus = try makeBus(overrides: ["JourneyCode": "JC123"])
        let initialStatus = TimingStatus(minutes: 5, status: 0)
        mock.timingStatusResult = initialStatus

        var now = Date()
        let viewModel = BusesViewModel(
            service: mock,
            timingStatusTTL: 10,
            dateProvider: { now }
        )

        await viewModel.fetchTimingStatus(for: bus)

        XCTAssertEqual(viewModel.timingStatus(for: bus.id), initialStatus)
        XCTAssertEqual(mock.fetchTimingStatusCallCount, 1)

        now = now.addingTimeInterval(11)
        mock.timingStatusResult = TimingStatus(minutes: 1, status: 1)

        await viewModel.fetchTimingStatus(for: bus)

        XCTAssertEqual(mock.fetchTimingStatusCallCount, 2)
        XCTAssertEqual(viewModel.timingStatus(for: bus.id)?.minutes, 1)
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
