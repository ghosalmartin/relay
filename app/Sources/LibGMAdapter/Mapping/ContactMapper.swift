import LibGMKit
import MessagingDomain

/// Google Messages address book → domain `Contact`s.
enum ContactMapper {
    /// Entries without a number are left out, because there's no way to message them.
    static func contacts(from response: GM.ListContactsResponse) -> [Contact] {
        response.contacts.compactMap { entry in
            guard !entry.number.number.isEmpty else { return nil }
            let displayNumber = entry.number.hasFormattedNumber ? entry.number.formattedNumber : entry.number.number
            return Contact(
                name: entry.name.isEmpty ? displayNumber : entry.name,
                phoneNumber: entry.number.number,
                displayNumber: displayNumber
            )
        }
    }
}
