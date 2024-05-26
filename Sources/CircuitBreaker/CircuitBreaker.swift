import Foundation

/// Global Actor to execute all Circuit Breaker relevant manipulations on
/// This is to guarantee thread safety
@globalActor public actor CircuitBreakerActor: GlobalActor {
    public static let shared = CircuitBreakerActor()
}

/**
 CircuitBreaker is a class that implements the circuit breaker pattern to manage the resiliency of network calls
 or other unreliable operations. It has three states: Closed, Open, and Half-Open.

 If the circuit is open, it throws an error. If half-open, it allows one attempt and resets if successful,
 otherwise opens again. If closed, it attempts normal operation and records failures.

 # Configuration: #
 - `name` / `group`: Strings to identify the circuit breaker
 - `maxFailures`: The number of failures before the circuit breaker trips to the open state.
 - `rollingWindow`: Time in seconds where failures are recorded.
 - `recoveryTimeout`: Time in seconds to wait before transitioning from open to half-open state.
 - `ErrorStrategy`: can be passed to trip on specific errors e.g. ignore network timeout / connectivity issues
 # Example: #
 maxFailures = 3, rollingWindow = 5sec, recoveryTimeout = 30sec
 If 3 failures happen within 5 seconds the breaker will open and all successive task will fail for the next 30 seconds.
 After the recovery time the breaker will be set to half open.
 */
@CircuitBreakerActor
public final class CircuitBreaker {
    enum State {
        case open
        case halfopen
        case closed
    }

    private(set) var state: State = .closed
    private var currentFailureTimestamps: [TimeInterval] = []
    private var config: Config
    private var lastOpenedTime: TimeInterval?
    private var lastError: Error?
    private var errorStrategy: CircuitBreakerErrorStrategy
    private var currentTime: () -> TimeInterval

    public convenience init(config: Config, errorStrategy: CircuitBreakerErrorStrategy = DefaultErrorStrategy()) {
        self.init(config: config, errorStrategy: errorStrategy) {
            Date.timeIntervalSinceReferenceDate
        }
    }

    init(config: Config, errorStrategy: CircuitBreakerErrorStrategy = DefaultErrorStrategy(), currentTime: @escaping () -> TimeInterval) {
        self.config = config
        self.errorStrategy = errorStrategy
        self.currentTime = currentTime
    }

    /// Executes a the task and updates the circuit state
    /// e.g. if task fails it will record a failure according to the configuration and `ErrorStrategy`.
    /// On successive failures - once the circuit opens, this will throw a `FastFailError` for
    /// a certain time window until the circuit is automatically closed again.
    /// - throws: `FastFailError` if circuit is open or any other error from the task
    func run<T>(_ task: @escaping () async throws -> T) async throws -> T {
        openIfResetTimeoutPassed()
        switch state {
        case .open:
            throw CircuitOpenError(lastError: lastError, name: config.name, group: config.group)
        case .closed, .halfopen:
            return try await handle(task: task)
        }
    }

    private func handle<T>(task: @escaping () async throws -> T) async rethrows -> T {
        let timeStamp = currentTime()
        // TODO: handle timeout
        do {
            let result = try await task()
            if state == .halfopen {
                close()
            }
            return result
        } catch {
            guard errorStrategy.shouldTrip(on: error) else {
                throw error
            }
            currentFailureTimestamps = Array(currentFailureTimestamps.prefix(config.maxFailures))
            currentFailureTimestamps.append(timeStamp)
            if state == .halfopen {
                // If failure on half open circuit - break immediately
                open()
            } else if let timeWindow = currentFailureTimeWindow,
                      currentFailureTimestamps.count >= config.maxFailures,
                      timeWindow <= config.rollingWindow
            {
                // Reached maximum number of failures allowed
                // in time window before tripping circuit
                open()
            }

            throw error
        }
    }

    private var currentFailureTimeWindow: TimeInterval? {
        guard let firstTimestamp = currentFailureTimestamps.first,
              let lastTimestamp = currentFailureTimestamps.last
        else {
            return nil
        }

        return lastTimestamp - firstTimestamp
    }

    private func openIfResetTimeoutPassed() {
        guard let lastOpenedTime else { return }
        let timeWindow = currentTime() - lastOpenedTime
        guard timeWindow >= config.recoveryTimeout else { return }
        self.lastOpenedTime = nil
        state = .halfopen
    }

    public func open() {
        state = .open
        lastOpenedTime = currentTime()
    }

    public func close() {
        currentFailureTimestamps.removeAll()
        lastOpenedTime = nil
        state = .closed
    }
}

public extension CircuitBreaker {
    struct Config {
        /// Name of the service or category of tasks
        var name: String
        /// Optional group name for debugging purposes
        var group: String?
        /// Time to wait before transitioning from open to half-open state
        var recoveryTimeout: TimeInterval
        /// Maximum number of failures allowed within the rolling window
        var maxFailures: Int
        /// Time period within which failures are counted to trigger the open state
        var rollingWindow: TimeInterval

        public init(
            name: String,
            group: String?,
            recoveryTimeout: TimeInterval,
            maxFailures: Int,
            rollingWindow: TimeInterval
        ) {
            self.name = name
            self.group = group
            self.recoveryTimeout = recoveryTimeout
            self.maxFailures = max(0, maxFailures)
            self.rollingWindow = rollingWindow
        }
    }

    struct DefaultErrorStrategy: CircuitBreakerErrorStrategy {
        public func shouldTrip(on error: any Error) -> Bool { true }
        public init() {}
    }
}

public protocol CircuitBreakerErrorStrategy {
    func shouldTrip(on error: Error) -> Bool
}

/// Error thrown if the circuit breaker is open
struct CircuitOpenError: Error {
    let lastError: Error?
    let name: String
    let group: String?
}
