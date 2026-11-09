import Foundation
import MessagingDomain
import Synchronization

/// Contact photos already fetched, so an alert can show one without waiting on a phone that may not answer.
public final class AvatarBook: Sendable {
    private let photos = Mutex<[ParticipantID: Data]>([:])

    public init() {}

    public func photo(of participant: ParticipantID) -> Data? {
        photos.withLock { $0[participant] }
    }

    func add(_ loaded: [ParticipantID: Data]) {
        photos.withLock { $0.merge(loaded) { _, latest in latest } }
    }
}
