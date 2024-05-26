import Foundation

@available(*, unavailable, message: "Implementation in progress, do not use.")
@CircuitBreakerActor
private final class CircuitBreakerGroup<Key: Hashable & CustomStringConvertible> {
    let name: String
    let baseConfig: CircuitBreaker.Config
    private var collection: [Key: CircuitBreaker] = [:]
    private var purgeTask: Task<Void, Never>?

    init(name: String, baseConfig: CircuitBreaker.Config) {
        self.name = name
        self.baseConfig = baseConfig
    }

    func run<T>(key: Key, task: @escaping () async throws -> T) async throws -> T {
        let breaker = getBreaker(key: key)
        let result = try await breaker.run(task)

        return result
    }

    private func getBreaker(key: Key) -> CircuitBreaker {
        let circuitBreaker: CircuitBreaker

        if let breaker = collection[key] {
            circuitBreaker = breaker
        } else {
            circuitBreaker = newCircuitBreaker(for: key)
            collection[key] = circuitBreaker
        }

        return circuitBreaker
    }

    private func newCircuitBreaker(for key: Key) -> CircuitBreaker {
        var config = baseConfig
        config.group = name
        config.name = key.description
        let breaker = CircuitBreaker(config: config)
        return breaker
    }

    private func purge() {}

    public func openAll() {
        collection.values.forEach { $0.open() }
    }

    public func closeAll() {
        collection.values.forEach { $0.close() }
    }
}
