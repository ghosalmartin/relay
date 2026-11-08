import Foundation

/// libgm timestamps are microseconds since the Unix epoch.
enum Timestamps {
    static func date(fromMicroseconds microseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(microseconds) / 1_000_000)
    }
}
