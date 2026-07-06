import AppKit

/// Floating, non-activating utility panel that stays above normal windows,
/// follows all regular Spaces, and never steals focus from the app being
/// typed into. It deliberately does *not* join full-screen Spaces — no
/// `.fullScreenAuxiliary` — so it disappears whenever another app goes
/// full-screen instead of floating over it.
final class HUDPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        setFrameAutosaveName("RoBaHUDPanel")
        self.contentView = contentView
        alphaValue = Prefs.opacity
    }

    // .nonactivatingPanel panels refuse key by default; the binding picker's
    // search field (M5) needs key status without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
