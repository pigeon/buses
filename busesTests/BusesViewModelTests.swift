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

    func testFetchTimingStatusDeduplicatesInFlightRequests() async throws {
        let mock = MockBusService()
        mock.timingStatusDelayNanoseconds = 100_000_000
        mock.timingStatusResult = TimingStatus(minutes: 3, status: 0)
        let bus = try makeBus(overrides: ["JourneyCode": "JC123"])
        let viewModel = BusesViewModel(service: mock)

        let task1 = Task { await viewModel.fetchTimingStatus(for: bus) }
        let task2 = Task { await viewModel.fetchTimingStatus(for: bus) }
        _ = await (task1.value, task2.value)

        XCTAssertEqual(mock.fetchTimingStatusCallCount, 1)
    }

    func testRefreshPrunesCachedTimingStatusesForMissingBuses() async throws {
        let mock = MockBusService()
        let bus1 = try makeBus(overrides: ["JourneyCode": "JC123"])
        let bus2 = try makeBus(overrides: ["JourneyCode": "JC456", "VehicleRef": "Vehicle-99"])

        mock.busesResult = [bus1]
        var now = Date()
        let viewModel = BusesViewModel(service: mock, timingStatusTTL: 300, dateProvider: { now })

        await viewModel.refresh(shouldUpdateCamera: false)
        await viewModel.fetchTimingStatus(for: bus1)

        XCTAssertNotNil(viewModel.timingStatus(for: bus1.id))

        mock.busesResult = [bus2]
        now = now.addingTimeInterval(60)

        await viewModel.refresh(shouldUpdateCamera: false)

        XCTAssertNil(viewModel.timingStatus(for: bus1.id))
        XCTAssertEqual(viewModel.buses, [bus2])
    }
}

private final class MockBusService: BusServiceProtocol {
    var busesResult: [Bus] = []
    var timingStatusResult: TimingStatus?
    var timingStatusDelayNanoseconds: UInt64 = 0
    private(set) var fetchBusesCallCount = 0
    private(set) var fetchTimingStatusCallCount = 0

    func fetchBuses() async throws -> [Bus] {
        fetchBusesCallCount += 1
        return busesResult
    }

    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus? {
        fetchTimingStatusCallCount += 1
        if timingStatusDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: timingStatusDelayNanoseconds)
        }
        return timingStatusResult
    }
}
