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
        if let pairing = pairingFailure(lowered) { return .backend(pairing) }
        if lowered.contains("client init timed out") { return .phoneMissedPairing }
        if lowered.contains("not logged in") || lowered.contains("unpaired") { return .notPaired }
        if lowered.contains("timeout") || lowered.contains("not responding") || lowered.contains("did not respond") { return .phoneUnreachable }
        return .backend(reason)
    }

    /// Wording follows libgm's own project. The inactive check comes first because libgm appends it to the timeout.
    private static func pairingFailure(_ lowered: String) -> String? {
        if lowered.contains("hasn't been seen recently") {
            return "Messages on your phone hasn't connected to this Google account recently. Open Messages, tap your profile picture, then Device pairing, and try again."
        }
        if lowered.contains("no devices found") {
            return "No phone found for this Google account. Sign in with the account used in Messages on your phone."
        }
        if lowered.contains("incorrect emoji") { return "The wrong emoji was tapped on your phone. Please try again." }
        if lowered.contains("cancelled pairing") { return "Pairing was cancelled on your phone." }
        if lowered.contains("pairing timed out") { return "The emoji wasn't tapped in time. Please try again." }
        return nil
    }
}
