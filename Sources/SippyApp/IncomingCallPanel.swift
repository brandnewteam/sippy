import AppKit
import SwiftUI

/// A ringing call can be handled with the mouse while the other app keeps
/// receiving keystrokes, including when its window occupies a full-screen Space.
@MainActor
final class IncomingCallPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(engine: SIPEngine) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 448, height: 76),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Incoming call"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false
        isExcludedFromWindowsMenu = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let host = CallPanelHostingView(rootView: IncomingCallBanner(engine: engine))
        host.sizingOptions = []
        contentView = host
        NotificationCenter.default.addObserver(self, selector: #selector(positionBelowMenuBar),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func present() {
        positionBelowMenuBar()
        orderFrontRegardless()
    }

    @objc private func positionBelowMenuBar() {
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        guard let display = (isVisible ? screen : nil) ?? pointerScreen ?? NSScreen.main else { return }
        let topInset = max(display.safeAreaInsets.top, NSStatusBar.system.thickness)
        let top = min(display.visibleFrame.maxY, display.frame.maxY - topInset)
        setFrameTopLeftPoint(NSPoint(x: (display.frame.midX - frame.width / 2).rounded(), y: top - 8))
    }
}

private final class CallPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct IncomingCallBanner: View {
    let engine: SIPEngine
    @AppStorage(SippyScheme.defaultsKey) private var scheme = SippyScheme.enamel
    @AppStorage(SippyMode.defaultsKey) private var mode = SippyMode.dark

    var body: some View {
        let dark = mode.colorScheme.map { $0 == .dark } ?? SystemAppearance.shared.isDark
        let theme = SippyTheme.resolve(scheme, dark: dark)
        if let call = engine.call, call.phase == .ringingIncoming {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(call.remoteDisplay)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(call.remoteNumber.isEmpty || call.remoteNumber == call.remoteDisplay
                         ? "Incoming call" : "Incoming call · \(call.remoteNumber)")
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                HStack(spacing: 7) {
                    Button {
                        if engine.call?.phase == .ringingIncoming { engine.decline() }
                    } label: { Label("Decline", systemImage: "phone.down.fill") }
                    .buttonStyle(PillButtonStyle(kind: .hangUp))
                    Button {
                        if engine.call?.phase == .ringingIncoming { engine.answer() }
                    } label: { Label("Answer", systemImage: "phone.fill") }
                    .buttonStyle(PillButtonStyle(kind: .call))
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.small)
                .frame(width: 178)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.paneTop, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.sippyTheme, theme)
        }
    }
}
