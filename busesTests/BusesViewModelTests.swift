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

    func testFetchTimingStatusUsesCacheWithinLifetime() async throws {
        let mock = MockBusService()
        let bus = try makeBus(overrides: ["JourneyCode": "JC123"])
        let expectedStatus = TimingStatus(minutes: 4, status: 2)
        mock.timingStatusResult = expectedStatus
        let viewModel = BusesViewModel(service: mock, timingStatusCacheLifetime: 30)
        let now = Date(timeIntervalSince1970: 1_000)

        await viewModel.fetchTimingStatus(for: bus, now: now)
        await viewModel.fetchTimingStatus(for: bus, now: now.addingTimeInterval(10))

        XCTAssertEqual(mock.fetchTimingStatusCallCount, 1)
        XCTAssertEqual(viewModel.timingStatus(for: bus.id), expectedStatus)
    }

    func testFetchTimingStatusRefreshesAfterCacheExpires() async throws {
        let mock = MockBusService()
        let bus = try makeBus(overrides: ["JourneyCode": "JC123"])
        let firstStatus = TimingStatus(minutes: 1, status: 0)
        let secondStatus = TimingStatus(minutes: 7, status: 2)
        mock.timingStatusResults = [firstStatus, secondStatus]
        let viewModel = BusesViewModel(service: mock, timingStatusCacheLifetime: 30)
        let now = Date(timeIntervalSince1970: 2_000)

        await viewModel.fetchTimingStatus(for: bus, now: now)
        await viewModel.fetchTimingStatus(for: bus, now: now.addingTimeInterval(31))

        XCTAssertEqual(mock.fetchTimingStatusCallCount, 2)
        XCTAssertEqual(viewModel.timingStatus(for: bus.id), secondStatus)
    }
}

private final class MockBusService: BusServiceProtocol {
    var busesResult: [Bus] = []
    var timingStatusResult: TimingStatus?
    var timingStatusResults: [TimingStatus?] = []
    private(set) var fetchBusesCallCount = 0
    private(set) var fetchTimingStatusCallCount = 0

    func fetchBuses() async throws -> [Bus] {
        fetchBusesCallCount += 1
        return busesResult
    }

    func fetchTimingStatus(journeyCode: String) async throws -> TimingStatus? {
        fetchTimingStatusCallCount += 1
        if !timingStatusResults.isEmpty {
            return timingStatusResults.removeFirst()
        }
        return timingStatusResult
    }
}
