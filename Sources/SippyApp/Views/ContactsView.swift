import AppKit
import SwiftUI
import SippyCore

/// One row of the contacts list, whichever source it comes from.
struct ContactItem: Identifiable {
    struct Number: Identifiable {
        let id: Int
        let label: String
        let value: String
    }

    let id: String
    let name: String
    let company: String
    let numbers: [Number]
    /// Sippy contacts dial verbatim; address book numbers go through the
    /// dial plan (outside line prefix).
    let origin: NumberOrigin
    /// Set for Sippy contacts: the row then offers favorite/edit/delete.
    let sippy: SippyContact?

    init(_ contact: SippyContact) {
        id = "sippy-\(contact.id.uuidString)"
        name = contact.name
        company = contact.company
        numbers = contact.numbers.enumerated().map {
            Number(id: $0.offset, label: $0.element.label, value: $0.element.value)
        }
        origin = .internalContact
        sippy = contact
    }

    init(_ entry: SystemContactsIndex.Entry) {
        id = "system-\(entry.id)"
        name = entry.name
        company = entry.company
        numbers = entry.numbers.enumerated().map {
            Number(id: $0.offset, label: $0.element.label, value: $0.element.value)
        }
        origin = .systemContact
        sippy = nil
    }

    func matches(_ needle: String) -> Bool {
        name.lowercased().contains(needle)
            || company.lowercased().contains(needle)
            || numbers.contains { PhoneNumberMatcher.normalize($0.value).contains(needle) }
    }
}

struct ContactsView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Environment(SystemContactsIndex.self) private var systemContacts
    @Environment(\.sippyTheme) private var theme

    @ViewState private var search = ""
    @ViewState private var expanded: Set<String> = []
    @ViewState private var editing: SippyContact?
    @ViewState private var deleting: SippyContact?
    @ViewState private var creating = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if hasNoMatches {
                ContentUnavailableView.search(text: search)
            } else {
                list
            }
        }
        .sheet(isPresented: $creating) {
            ContactEditor(contact: nil)
        }
        .sheet(item: $editing) { contact in
            ContactEditor(contact: contact)
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { contact in
            Button("Delete", role: .destructive) { store.deleteContact(contact.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The contact is removed from Sippy. Your address book is not touched.")
        }
        .onAppear { systemContacts.loadIfAuthorized() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand { search = "" }
                if !search.isEmpty {
                    Button {
                        search = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.controlFill))

            Button {
                creating = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Sippy contact")
            .accessibilityLabel("New Sippy contact")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var list: some View {
        List {
            let sippy = sippyItems
            let favorites = sippy.filter { $0.sippy?.isFavorite == true }
            let others = sippy.filter { $0.sippy?.isFavorite != true }

            if !favorites.isEmpty {
                section("Favorites") { rows(favorites) }
            }
            if !others.isEmpty {
                section("Sippy") { rows(others) }
            } else if store.contacts.isEmpty {
                section("Sippy") {
                    SourceNote(
                        text: "Extensions and internal numbers live here. They are dialed exactly as written.",
                        action: "New Contact…"
                    ) { creating = true }
                }
            }
            systemSection
        }
        .listStyle(.inset)
        // The pane shows through; the list brings no background.
        .scrollContentBackground(.hidden)
    }

    /// A titled group of rows. The title is a row of its own rather than a
    /// section header: headers pin to the top over a system material, a
    /// gray band across the pane.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Section {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func rows(_ items: [ContactItem]) -> some View {
        ForEach(items) { item in
            ContactRow(
                item: item,
                // A search that hit one of several numbers opens the row, so
                // the match is on screen.
                isExpanded: expanded.contains(item.id) || matchedByNumberOnly(item),
                toggle: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if expanded.contains(item.id) {
                            expanded.remove(item.id)
                        } else {
                            expanded.insert(item.id)
                        }
                    }
                },
                onEdit: { editing = item.sippy },
                onDelete: { deleting = item.sippy })
        }
    }

    @ViewBuilder
    private var systemSection: some View {
        switch systemContacts.access {
        case .authorized:
            let matches = systemItems
            if !matches.isEmpty {
                section("Address Book") { rows(matches) }
            }
        case .undetermined:
            section("Address Book") {
                SourceNote(
                    text: "Search and call the people in Contacts, and see their names when they call.",
                    action: "Show Address Book…"
                ) { systemContacts.requestAccess() }
            }
        case .denied:
            section("Address Book") {
                SourceNote(
                    text: "Sippy has no access to Contacts. Allow it in System Settings › Privacy & Security › Contacts.",
                    action: "Open Privacy Settings…"
                ) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Data

    /// A search that finds nothing in either source.
    private var hasNoMatches: Bool {
        !search.isEmpty && sippyItems.isEmpty
            && (systemContacts.access != .authorized || systemItems.isEmpty)
    }

    private var needle: String { search.lowercased() }

    private func matchedByNumberOnly(_ item: ContactItem) -> Bool {
        !search.isEmpty
            && !item.name.lowercased().contains(needle)
            && !item.company.lowercased().contains(needle)
    }

    private var sippyItems: [ContactItem] {
        store.contacts
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(ContactItem.init)
            .filter { search.isEmpty || $0.matches(needle) }
    }

    private var systemItems: [ContactItem] {
        systemContacts.entries
            .map(ContactItem.init)
            .filter { search.isEmpty || $0.matches(needle) }
    }
}

/// A contact: monogram, name, and on the right the one thing you came for.
/// With a single number that is the call button; with several, the row
/// opens to list them, each with its own call button.
struct ContactRow: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    let item: ContactItem
    let isExpanded: Bool
    let toggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewState private var hovering = false

    private var hasSeveralNumbers: Bool { item.numbers.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Monogram(name: item.name, diameter: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let contact = item.sippy {
                    actionsMenu(contact)
                        // Laid out but invisible until hover, so the row
                        // doesn't shift. The context menu has the same
                        // actions for keyboard and VoiceOver users.
                        .opacity(hovering ? 1 : 0)
                }
                trailingControl
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture { if hasSeveralNumbers { toggle() } }

            if isExpanded, hasSeveralNumbers {
                VStack(spacing: 4) {
                    ForEach(item.numbers) { number in
                        NumberRow(label: number.label, value: number.value) {
                            engine.dial(number.value, origin: item.origin)
                        }
                    }
                }
                // Aligned with the name, past the monogram.
                .padding(.leading, 40)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
        .onHover { hovering = $0 }
        .sippyListRow()
        .contextMenu { contextMenu }
    }

    /// The number when there is just one, so most calls need no second
    /// look; a count otherwise. Then the company.
    private var subtitle: String {
        var parts: [String] = []
        if hasSeveralNumbers {
            parts.append("\(item.numbers.count) numbers")
        } else if let number = item.numbers.first {
            parts.append(number.value)
        }
        if !item.company.isEmpty, item.company != item.name {
            parts.append(item.company)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailingControl: some View {
        if hasSeveralNumbers {
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide numbers" : "Show numbers")
            .accessibilityLabel(isExpanded ? "Hide numbers" : "Show numbers")
        } else if let number = item.numbers.first {
            RowCallButton {
                engine.dial(number.value, origin: item.origin)
            }
            .help(number.label.isEmpty ? "Call \(number.value)" : "Call \(number.label): \(number.value)")
        }
    }

    private func actionsMenu(_ contact: SippyContact) -> some View {
        Menu {
            sippyActions(contact)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Edit, favorite or delete")
        .accessibilityLabel("Contact actions")
    }

    @ViewBuilder
    private var contextMenu: some View {
        if !hasSeveralNumbers, let number = item.numbers.first {
            Button("Copy Number") { copyToPasteboard(number.value) }
        }
        if let contact = item.sippy {
            if item.numbers.count == 1 { Divider() }
            sippyActions(contact)
        }
    }

    @ViewBuilder
    private func sippyActions(_ contact: SippyContact) -> some View {
        Button(contact.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            store.toggleFavorite(contact.id)
        }
        Button("Edit…") { onEdit() }
        Divider()
        Button("Delete…", role: .destructive) { onDelete() }
    }
}

/// One number of a contact that has several.
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
            Spacer(minLength: 4)
            RowCallButton(action: dial)
        }
        .contextMenu {
            Button("Copy Number") { copyToPasteboard(value) }
        }
    }
}

/// Explains an empty or unavailable contact source and offers the way out.
struct SourceNote: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .buttonStyle(PaneLinkButtonStyle())
        }
        .padding(.vertical, 4)
        .sippyListRow()
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
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
