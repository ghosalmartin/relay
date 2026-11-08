/// Polls `condition` every millisecond until it holds or `timeout` passes.
/// For tests that must wait for a background task (e.g. a subscriber to start listening).
/// Returns whether the condition was met, so callers can `#expect` on it.
@discardableResult
public func eventually(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// The first `count` elements, or fewer if the sequence ends first.
    public func first(_ count: Int) async rethrows -> [Element] {
        var out: [Element] = []
        for try await element in self {
            out.append(element)
            if out.count == count { break }
        }
        return out
    }
}
