import SwiftUI
import SippyCore

struct ContactsView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Environment(SystemContactsIndex.self) private var systemContacts

    @State private var search = ""
    @State private var editing: SippyContact?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Sippy contact")
            }
            .padding(10)

            List {
                let sippyMatches = filteredContacts
                if !sippyMatches.isEmpty {
                    Section("Sippy") {
                        ForEach(sippyMatches) { contact in
                            SippyContactRow(contact: contact) { editing = contact }
                        }
                    }
                }
                systemSection
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $creating) {
            ContactEditor(contact: nil)
        }
        .sheet(item: $editing) { contact in
            ContactEditor(contact: contact)
        }
        .onAppear { systemContacts.loadIfAuthorized() }
    }

    private var filteredContacts: [SippyContact] {
        guard !search.isEmpty else {
            return store.contacts.sorted {
                ($0.isFavorite ? 0 : 1, $0.name.lowercased()) < ($1.isFavorite ? 0 : 1, $1.name.lowercased())
            }
        }
        let needle = search.lowercased()
        return store.contacts.filter { contact in
            contact.name.lowercased().contains(needle)
                || contact.company.lowercased().contains(needle)
                || contact.numbers.contains { PhoneNumberMatcher.normalize($0.value).contains(needle) }
        }
    }

    @ViewBuilder
    private var systemSection: some View {
        switch systemContacts.access {
        case .authorized:
            let matches = filteredSystemEntries
            if !matches.isEmpty {
                Section("Address Book") {
                    ForEach(matches) { entry in
                        SystemContactRow(entry: entry)
                    }
                }
            }
        case .undetermined:
            Section("Address Book") {
                Button("Show system contacts…") { systemContacts.requestAccess() }
                    .buttonStyle(.link)
            }
        case .denied:
            Section("Address Book") {
                Text("Access denied — enable in System Settings › Privacy › Contacts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var filteredSystemEntries: [SystemContactsIndex.Entry] {
        guard !search.isEmpty else { return systemContacts.entries }
        let needle = search.lowercased()
        return systemContacts.entries.filter { entry in
            entry.name.lowercased().contains(needle)
                || entry.company.lowercased().contains(needle)
                || entry.numbers.contains { PhoneNumberMatcher.normalize($0.value).contains(needle) }
        }
    }
}

struct SippyContactRow: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    let contact: SippyContact
    let onEdit: () -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(contact.numbers) { number in
                NumberRow(label: number.label, value: number.value) {
                    engine.dial(number.value, origin: .internalContact)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if contact.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                }
                VStack(alignment: .leading) {
                    Text(contact.name)
                    if !contact.company.isEmpty {
                        Text(contact.company).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu {
            Button(contact.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(contact.id)
            }
            Button("Edit…") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { store.deleteContact(contact.id) }
        }
    }
}

struct SystemContactRow: View {
    @Environment(SIPEngine.self) private var engine
    let entry: SystemContactsIndex.Entry

    var body: some View {
        DisclosureGroup {
            ForEach(Array(entry.numbers.enumerated()), id: \.offset) { _, number in
                NumberRow(label: number.label, value: number.value) {
                    engine.dial(number.value, origin: .systemContact)
                }
            }
        } label: {
            VStack(alignment: .leading) {
                Text(entry.name)
                if !entry.company.isEmpty {
                    Text(entry.company).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct NumberRow: View {
    @Environment(SIPEngine.self) private var engine
    let label: String
    let value: String
    let dial: () -> Void

    var body: some View {
        HStack {
            Text(label.isEmpty ? "phone" : label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
            Button {
                dial()
            } label: {
                Image(systemName: "phone.fill").foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(engine.registration != .registered || engine.call != nil)
        }
    }
}

struct ContactEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let contact: SippyContact?

    @State private var draft = SippyContact(name: "", numbers: [ContactNumber(label: "extension", value: "")])
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $draft.name)
                TextField("Company", text: $draft.company)
                Toggle("Favorite", isOn: $draft.isFavorite)
                Section("Numbers") {
                    ForEach($draft.numbers) { $number in
                        HStack {
                            TextField("Label", text: $number.label)
                                .frame(width: 110)
                            TextField("Number or extension", text: $number.value)
                            Button {
                                draft.numbers.removeAll { $0.id == number.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(draft.numbers.count == 1)
                        }
                    }
                    Button("Add Number") {
                        draft.numbers.append(ContactNumber(label: "work", value: ""))
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 380, height: 440)
        .onAppear(perform: loadOnce)
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let contact { draft = contact }
    }

    private func save() {
        var contact = draft
        contact.numbers = contact.numbers.filter {
            !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        store.upsert(contact)
        dismiss()
    }
}
