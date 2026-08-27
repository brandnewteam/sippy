import Contacts
import Foundation
import Observation

/// Read-only view of the system address book: shown alongside Sippy contacts
/// in search and used for caller-ID. Numbers dialed from here get the outside
/// line prefix (origin `.systemContact`).
@MainActor
@Observable
final class SystemContactsIndex {
    struct Entry: Identifiable, Hashable {
        let id: String
        let name: String
        let company: String
        let numbers: [(label: String, value: String)]

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    enum Access { case undetermined, denied, authorized }

    private(set) var access: Access = .undetermined
    private(set) var entries: [Entry] = []

    func loadIfAuthorized() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            access = .authorized
            reload()
        case .denied, .restricted:
            access = .denied
        case .notDetermined:
            access = .undetermined
        @unknown default:
            access = .denied
        }
    }

    func requestAccess() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            Task { @MainActor in
                self.access = granted ? .authorized : .denied
                if granted { self.reload() }
            }
        }
    }

    private func reload() {
        Task.detached(priority: .userInitiated) {
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey, CNContactFamilyNameKey,
                CNContactOrganizationNameKey, CNContactPhoneNumbersKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var result: [Entry] = []
            try? store.enumerateContacts(with: request) { contact, _ in
                guard !contact.phoneNumbers.isEmpty else { return }
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                let numbers = contact.phoneNumbers.map { labeled in
                    (label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: labeled.label ?? ""),
                     value: labeled.value.stringValue)
                }
                result.append(Entry(
                    id: contact.identifier,
                    name: name.isEmpty ? contact.organizationName : name,
                    company: contact.organizationName,
                    numbers: numbers))
            }
            let entries = result
            await MainActor.run { self.entries = entries }
        }
    }
}
