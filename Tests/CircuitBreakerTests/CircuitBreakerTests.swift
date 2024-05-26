@testable import CircuitBreaker
import XCTest

final class CircuitBreakerTests: XCTestCase {
    var config: CircuitBreaker.Config = .init(
        name: "test",
        group: "xctests",
        recoveryTimeout: 30,
        maxFailures: 5,
        rollingWindow: 15
    )

    var shortTripConfig: CircuitBreaker.Config = .init(
        name: "test",
        group: "xctests",
        recoveryTimeout: 20,
        maxFailures: 3,
        rollingWindow: 10
    )

    func testClosedStateOneTask() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: config) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.success("ok"), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [.success("ok")])
    }

    // test trip on x failure in n time

    func testClosedStateManyTasksNotOpen() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: config) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.success("0"), 1),
                (.success("1"), 1),
                (.success("2"), 1),
                (.success("3"), 1),
                (.success("4"), 1),
                (.success("5"), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .success("0"),
            .success("1"),
            .success("2"),
            .success("3"),
            .success("4"),
            .success("5"),
        ])
    }

    func testOpenOnAllFailuresWithinWindow() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: config) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(CircuitOpenError(lastError: nil, name: "", group: nil).equatable),
        ])
    }

    func testOpenOnSomeFailuresWithinWindow() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: config) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.success("ok"), 1),
                (.failure(SubTaskError()), 1),
                (.success("ok"), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1), // Trips
                (.success("ok"), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .success("ok"),
            .failure(SubTaskError().equatable),
            .success("ok"),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(CircuitOpenError(lastError: nil, name: "", group: nil).equatable),
        ])
    }

    func testNotOpenOnManyFailuresOutsideWindow() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: config) {
            currentTime
        }

        // When
        let delayToTripOn6th = 3.75
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.failure(SubTaskError()), delayToTripOn6th),
                (.failure(SubTaskError()), delayToTripOn6th),
                (.failure(SubTaskError()), delayToTripOn6th),
                (.failure(SubTaskError()), delayToTripOn6th),
                (.failure(SubTaskError()), delayToTripOn6th),
                (.failure(SubTaskError()), delayToTripOn6th),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(CircuitOpenError(lastError: nil, name: "", group: nil).equatable),
        ])
    }

    func testOpenThenRecoverToHalfOpenThenOpen() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: shortTripConfig) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1), // Trips
                (.success("ok"), 20), // Recover
                (.failure(SubTaskError()), 1), // Trips again
                (.success("ok"), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(CircuitOpenError(lastError: nil, name: "", group: nil).equatable),
            .failure(SubTaskError().equatable),
            .failure(CircuitOpenError(lastError: nil, name: "", group: nil).equatable),
        ])
    }

    func testOpenThenRecoverToHalfOpenThenClose() async throws {
        // Given
        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: shortTripConfig) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1), // Trips
                (.success("ok"), 20), // Recover
                (.success("ok"), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(CircuitOpenError(lastError: nil, name: "", group: nil).equatable),
            .success("ok"),
        ])
    }

    func testCancelTasksNotOpen() async throws {
        // Given
        let currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: shortTripConfig) {
            currentTime
        }

        // When
        let (t1, t1r) = await submitTask(to: sut, result: .failure(SubTaskError()))
        let (t2, t2r) = await submitTask(to: sut, result: .failure(SubTaskError()))
        let (t3, t3r) = await submitTask(to: sut, result: .failure(SubTaskError()))
        let (t4, t4r) = await submitTask(to: sut, result: .success("ok"))

        await t1.cancel()
        await t2.cancel()
        await t3.cancel()
        await t4.unblock()

        let breakerResults = await [
            t1r.result.mapError(\.equatable),
            t2r.result.mapError(\.equatable),
            t3r.result.mapError(\.equatable),
            t4r.result.mapError(\.equatable),
        ]

        // Then
        XCTAssertEqual(breakerResults, [
            .failure(CancellationError().equatable),
            .failure(CancellationError().equatable),
            .failure(CancellationError().equatable),
            .success("ok"),
        ])
    }

    // test error strategy

    func testErrorStrategyNotOpen() async throws {
        // Given
        struct CustomErrorStrategy: CircuitBreakerErrorStrategy {
            func shouldTrip(on error: any Error) -> Bool {
                guard error is SubTaskError else {
                    return true
                }

                return false
            }
        }

        var currentTime: TimeInterval = 0
        let sut = await CircuitBreaker(config: shortTripConfig, errorStrategy: CustomErrorStrategy()) {
            currentTime
        }

        // When
        let results = await runTasks(
            on: sut,
            currentTime: &currentTime,
            results: [
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.failure(SubTaskError()), 1),
                (.success("ok"), 1),
            ]
        )

        // Then
        XCTAssertEqual(results, [
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .failure(SubTaskError().equatable),
            .success("ok"),
        ])
    }

    func testPerformanceAndMemory() throws {
        throw XCTSkip("Run on device only")

        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            let exp = expectation(description: "Finished")
            Task {
                var currentTime: TimeInterval = 0
                let sut = await CircuitBreaker(config: config) {
                    currentTime
                }

                for i in 0 ..< 100_000 {
                    let (t, r) = await submitTask(to: sut, result: .success("\(i)"))
                    await t.unblock()
                    _ = await r.result
                    currentTime += 1.0
                }
                exp.fulfill()
            }
            wait(for: [exp], timeout: 200.0)
        }
    }

    private struct SubTaskError: CustomNSError {
        static let errorDomain = "SubTaskError"
    }
}

private func runTasks(
    on breaker: CircuitBreaker,
    currentTime: inout TimeInterval,
    results: [(mockResult: Result<String, Error>, delay: TimeInterval)]
) async -> [Result<String, EquatableError>] {
    var breakerResults: [Result<String, EquatableError>] = []

    for (result, delay) in results {
        let (t1, t1r) = await submitTask(to: breaker, result: result)
        await t1.unblock()

        await breakerResults.append(
            t1r.result.mapError(\.equatable)
        )

        currentTime += delay
    }

    return breakerResults
}

private func submitTask(
    to breaker: CircuitBreaker,
    result: Result<String, Error>
) async -> (subTask: BarrierTask<String>, breakerResultTask: Task<String, Error>) {
    let barrierTask = await BarrierTask(result: result)
    let resultTask = Task {
        do {
            return try await breaker.run {
                try await barrierTask.run()
            }
        } catch {
            throw error
        }
    }

    return (barrierTask, resultTask)
}

extension Result: CustomDebugStringConvertible where
    Success: CustomDebugStringConvertible,
    Failure: CustomDebugStringConvertible
{
    public var debugDescription: String {
        switch self {
        case let .success(value): "success(\(value.debugDescription))"
        case let .failure(error): "failure(\(error.debugDescription))"
        }
    }
}

private actor BarrierTask<Success> where Success: Sendable {
    private var task: Task<Success, Error>!
    private var isBlocked = true

    init(result: Result<Success, Error>) async {
        task = Task {
            while isBlocked {
                try Task.checkCancellation()
                await Task.yield()
            }
            return try result.get()
        }
    }

    func run() async throws -> Success {
        try await task.result.get()
    }

    func unblock() async {
        isBlocked = false
    }

    func cancel() async {
        task.cancel()
        _ = try? await task.result.get()
    }
}

private struct EquatableError: Error, Equatable, CustomDebugStringConvertible {
    let error: Error
    let equalTo: (Error) -> Bool

    init(_ error: Error) {
        self.error = error
        equalTo = { other in
            let lhs = other as NSError
            let rhs = error as NSError
            return (lhs.domain, lhs.code) == (rhs.domain, rhs.code)
        }
    }

    var debugDescription: String {
        let nsError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.equalTo(rhs.error)
    }
}

private extension Error {
    var equatable: EquatableError {
        EquatableError(self)
    }
}
