import Foundation
import Observation
import SippyCore

/// A phone number (or bare PBX extension) attached to a Sippy contact.
struct ContactNumber: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String
    var value: String
}

/// Sippy's own contact — the home for internal/PBX numbers the system address
/// book can't sensibly hold. Numbers here dial verbatim (no outside prefix).
struct SippyContact: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var company: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var numbers: [ContactNumber] = []
}

struct CallRecord: Codable, Hashable, Identifiable {
    enum Direction: String, Codable { case incoming, outgoing }
    enum Outcome: String, Codable { case answered, missed, declined, failed, unanswered }

    var id: UUID = UUID()
    var date: Date
    var direction: Direction
    var number: String
    var displayName: String
    var durationSeconds: Int
    var outcome: Outcome
    var codec: String?
}

/// Contacts and call history, persisted as JSON in Application Support.
/// (SwiftData was the original plan, but its macros ship only with full
/// Xcode; a JSON store is dependency-free and plenty at this scale.)
@MainActor
@Observable
final class AppStore {
    private(set) var contacts: [SippyContact] = []
    private(set) var records: [CallRecord] = []

    private let directory: URL
    private var contactsURL: URL { directory.appendingPathComponent("contacts.json") }
    private var historyURL: URL { directory.appendingPathComponent("history.json") }
    private static let historyLimit = 1000

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sippy", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        contacts = Self.read(contactsURL) ?? []
        records = Self.read(historyURL) ?? []
    }

    // MARK: - Contacts

    func upsert(_ contact: SippyContact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
        } else {
            contacts.append(contact)
        }
        contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistContacts()
    }

    func deleteContact(_ id: SippyContact.ID) {
        contacts.removeAll { $0.id == id }
        persistContacts()
    }

    func toggleFavorite(_ id: SippyContact.ID) {
        guard let index = contacts.firstIndex(where: { $0.id == id }) else { return }
        contacts[index].isFavorite.toggle()
        persistContacts()
    }

    /// Sippy-contact name for a number, if any (used for caller ID).
    func contactName(forNumber number: String) -> String? {
        for contact in contacts {
            if contact.numbers.contains(where: { PhoneNumberMatcher.matches($0.value, number) }) {
                return contact.name
            }
        }
        return nil
    }

    // MARK: - History

    func add(_ record: CallRecord) {
        records.insert(record, at: 0)
        if records.count > Self.historyLimit {
            records.removeLast(records.count - Self.historyLimit)
        }
        persistHistory()
    }

    func deleteRecord(_ id: CallRecord.ID) {
        records.removeAll { $0.id == id }
        persistHistory()
    }

    func clearHistory() {
        records.removeAll()
        persistHistory()
    }

    // MARK: - Persistence

    private func persistContacts() { Self.write(contacts, to: contactsURL) }
    private func persistHistory() { Self.write(records, to: historyURL) }

    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
