import SwiftUI
import SippyCore

struct DialpadView: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(AppStore.self) private var store
    @Binding var number: String
    @FocusState private var fieldFocused: Bool

    /// nil letters means the key has no letters row.
    private static let rows: [[(digit: String, letters: String?)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("*", nil), ("0", "+"), ("#", nil)],
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            display
            Spacer(minLength: 12)
            keypad
        }
        // The keypad stays anchored to the bottom, where the hand expects
        // it; a taller window only gives the number more air.
        .padding(.bottom, 20)
        .padding(.horizontal, SippyLayout.mainPadding)
        .onAppear { fieldFocused = true }
    }

    private var display: some View {
        VStack(spacing: 2) {
            TextField("Number", text: $number)
                .textFieldStyle(.plain)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .onSubmit(dial)
            // Always there, even when blank: the keypad must not jump when
            // the line appears.
            hintLine
                .font(.callout)
                .lineLimit(1)
                .frame(height: 18)
        }
    }

    /// Under the number: whose number it is, or why the last call failed.
    private var hintLine: Text {
        if let name = matchedName {
            Text(name).foregroundStyle(.secondary)
        } else if number.isEmpty, let error = engine.lastCallError {
            Text(error).foregroundStyle(.red)
        } else {
            Text(" ")
        }
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 14, verticalSpacing: 12) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.digit) { key in
                        DialKey(digit: key.digit, letters: key.letters) {
                            number.append(key.digit)
                        }
                    }
                }
            }
            // Same grid, so the call button sits under 0 and delete under #.
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])

                Button(action: dial) {
                    Image(systemName: "phone.fill")
                }
                .buttonStyle(CircleButtonStyle(kind: .call, diameter: 58))
                .disabled(engine.registration != .registered)
                .keyboardShortcut(.return, modifiers: [])
                .help(number.isEmpty ? "Bring back the last number dialed" : "Call")
                .accessibilityLabel(number.isEmpty ? "Redial" : "Call")

                Button {
                    if !number.isEmpty { number.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(number.isEmpty ? 0 : 1)
                .disabled(number.isEmpty)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
            .padding(.top, 6)
        }
    }

    /// Who the typed number belongs to, if it is a known contact.
    private var matchedName: String? {
        guard !number.isEmpty else { return nil }
        return engine.displayNameResolver?(number)
    }

    /// With a number: call it. Without one the call button works like a
    /// phone's redial — it brings back the last number dialed, ready to call.
    private func dial() {
        guard engine.registration == .registered else { return }
        guard !number.isEmpty else {
            if let last = store.records.first(where: { $0.direction == .outgoing }) {
                number = last.number
            }
            return
        }
        engine.dial(number, origin: .dialpad)
        number = ""
    }
}

struct DialKey: View {
    let digit: String
    let letters: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if digit == "*" {
                    // The text asterisk sits high and small; the symbol is
                    // optically centered.
                    Image(systemName: "asterisk")
                        .font(.system(size: 17, weight: .medium))
                } else {
                    Text(digit).font(.system(size: 24, weight: .regular, design: .rounded))
                }
                if let letters {
                    Text(letters)
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .frame(height: 11)
                }
            }
        }
        .buttonStyle(DialKeyStyle())
        .accessibilityLabel(digit)
    }
}
