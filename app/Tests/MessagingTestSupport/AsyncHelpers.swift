/// Polls `condition` every millisecond until it holds or `timeout` passes.
/// For tests that must wait for a background task (e.g. a subscriber to start listening).
/// Returns whether the condition was met, so callers can `#expect` on it.
/// Runs on the caller's actor, so `@MainActor` tests can read view-model state directly.
@discardableResult
public func eventually(
    timeout: Duration = .seconds(2),
    isolation: isolated (any Actor)? = #isolation,
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while await !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// The first `count` elements, or fewer if the sequence ends first.
    public func first(_ count: Int) async rethrows -> [Element] {
        try await prefix(count).reduce([]) { $0 + [$1] }
    }
}
