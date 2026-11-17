import SwiftUI
import SippyCore

struct ContactsView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Environment(SystemContactsIndex.self) private var systemContacts

    @ViewState private var search = ""
    @ViewState private var editing: SippyContact?
    @ViewState private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.sippyControlFill()))

                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("New Sippy contact")
                .accessibilityLabel("New Sippy contact")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 8)

            if hasNoMatches {
                ContentUnavailableView.search(text: search)
            } else {
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
        }
        .sheet(isPresented: $creating) {
            ContactEditor(contact: nil)
        }
        .sheet(item: $editing) { contact in
            ContactEditor(contact: contact)
        }
        .onAppear { systemContacts.loadIfAuthorized() }
    }

    /// A search that finds nothing in either source.
    private var hasNoMatches: Bool {
        !search.isEmpty && filteredContacts.isEmpty
            && (systemContacts.access != .authorized || filteredSystemEntries.isEmpty)
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
                ContactLabel(name: contact.name, company: contact.company)
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
            ContactLabel(name: entry.name, company: entry.company)
        }
    }
}

/// Name over company, shared by Sippy and address book rows.
struct ContactLabel: View {
    let name: String
    let company: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).lineLimit(1)
            if !company.isEmpty {
                Text(company).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct NumberRow: View {
    let label: String
    let value: String
    let dial: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label.isEmpty ? "phone" : label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            RowCallButton(action: dial)
        }
    }
}

struct ContactEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let contact: SippyContact?

    @ViewState private var draft = SippyContact(name: "", numbers: [ContactNumber(label: "extension", value: "")])
    @ViewState private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $draft.name)
                TextField("Company", text: $draft.company)
                Toggle("Favorite", isOn: $draft.isFavorite)
                Section("Numbers") {
                    ForEach($draft.numbers) { $number in
                        HStack(spacing: 8) {
                            TextField("Label", text: $number.label, prompt: Text("Label"))
                                .frame(width: 84)
                            TextField("Number", text: $number.value, prompt: Text("Number or extension"))
                            Button {
                                draft.numbers.removeAll { $0.id == number.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(draft.numbers.count == 1)
                            .help("Remove number")
                        }
                        .labelsHidden()
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

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        // As wide as the window it drops from.
        .frame(width: SippyLayout.mainWidth, height: 460)
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
