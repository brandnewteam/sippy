import SwiftUI
import SippyCore

struct MainView: View {
    @Environment(SIPEngine.self) private var engine

    var body: some View {
        VStack(spacing: 0) {
            RegistrationBanner()
            Divider()
            if engine.call != nil {
                CallView()
            } else {
                TabView {
                    DialpadView()
                        .tabItem { Label("Dialpad", systemImage: "circle.grid.3x3.fill") }
                    ContactsView()
                        .tabItem { Label("Contacts", systemImage: "person.2.fill") }
                    HistoryView()
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct RegistrationBanner: View {
    @Environment(SIPEngine.self) private var engine
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if case .unconfigured = engine.registration {
                Button("Set Up…") { openSettings() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch engine.registration {
        case .registered: .green
        case .connecting: .yellow
        case .failed: .red
        case .unconfigured: .gray
        case .waitingForRoute: .orange
        }
    }

    private var label: String {
        switch engine.registration {
        case .registered: "\(engine.account.username)@\(engine.account.domain)"
        case .connecting: "Connecting…"
        case .failed(let message): "Registration failed: \(message)"
        case .unconfigured: "No account configured"
        case .waitingForRoute: "Server unreachable — waiting for a route (VPN down?)"
        }
    }
}
