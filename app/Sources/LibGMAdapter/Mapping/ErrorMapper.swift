import LibGMKit
import MessagingDomain

/// libgm error → domain error, so nothing above the adapter sees libgm's types.
enum ErrorMapper {
    static func error(from error: LibGMError) -> MessagingError {
        switch error {
        case .invalidSavedSession, .closed: .notPaired
        case .malformed(let detail): .backend(detail)
        case .bridge(let reason): bridgeError(reason)
        }
    }

    /// libgm reports failures as text; recognise the ones the app reacts to.
    private static func bridgeError(_ reason: String) -> MessagingError {
        let lowered = reason.lowercased()
        if lowered.contains("not logged in") || lowered.contains("unpaired") { return .notPaired }
        if lowered.contains("timeout") || lowered.contains("not responding") { return .phoneUnreachable }
        return .backend(reason)
    }
}
