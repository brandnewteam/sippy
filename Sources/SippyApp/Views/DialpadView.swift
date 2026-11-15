import SwiftUI
import SippyCore

struct DialpadView: View {
    @Environment(SIPEngine.self) private var engine
    @ViewState private var number = ""
    @FocusState private var fieldFocused: Bool

    /// nil label means the key has no letters row.
    private static let keys: [(digit: String, letters: String?)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", nil), ("0", "+"), ("#", nil),
    ]

    var body: some View {
        VStack(spacing: 14) {
            TextField("Number", text: $number)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .light, design: .monospaced))
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .onSubmit(dial)
                .padding(.top, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 14), count: 3), spacing: 12) {
                ForEach(Self.keys, id: \.digit) { key in
                    DialKey(digit: key.digit, letters: key.letters) {
                        number.append(key.digit)
                    }
                }
            }

            HStack(spacing: 20) {
                Button {
                    if !number.isEmpty { number.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(number.isEmpty)

                Button(action: dial) {
                    Image(systemName: "phone.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(canDial ? .green : .gray))
                }
                .buttonStyle(.plain)
                .disabled(!canDial)
                .keyboardShortcut(.return, modifiers: [])
            }

            if let error = engine.lastCallError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .onAppear { fieldFocused = true }
    }

    private var canDial: Bool {
        !number.isEmpty && engine.registration == .registered
    }

    private func dial() {
        guard canDial else { return }
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
            VStack(spacing: 1) {
                Text(digit).font(.system(size: 22, weight: .regular))
                if let letters {
                    Text(letters).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}
