import AppKit
import SwiftUI

/// Full-screen counting mode: a borderless panel covering the screen under the
/// mouse. It's non-activating but still takes key status, so it can read Esc,
/// Space and the arrow keys without activating the app — macOS may refuse to
/// activate an accessory app from a key tap made in another app.
@MainActor
final class FullscreenController {
    private let state: AppState
    private var panel: FullscreenPanel?

    init(state: AppState) {
        self.state = state
    }

    func toggle() {
        if panel == nil { enter() } else { exit() }
    }

    func enter() {
        guard panel == nil, let screen = NSScreen.underMouse else { return }

        let hostingView = NSHostingView(rootView: FullscreenView(state: state))
        // The panel's frame is fixed to the screen; don't let SwiftUI size it.
        hostingView.sizingOptions = []

        // A fresh panel each time, so it always lands on the active Space (see
        // OverlayController.replacePanelIfOffActiveSpace).
        let p = FullscreenPanel(frame: screen.frame)
        p.contentView = hostingView
        p.onKeyDown = { [weak self] event in self?.handleKey(event) }
        p.onDismiss = { [weak self] in self?.exit() }
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        panel = p
        state.isFullscreen = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func exit() {
        guard let p = panel else { return }
        panel = nil
        p.onKeyDown = nil
        p.onDismiss = nil
        state.isFullscreen = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                p.orderOut(nil)
                p.contentView = nil
            }
        })
    }

    private func handleKey(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            exit()
        case 49 where !event.isARepeat: // Space
            state.increment()
        case 123 where !event.isARepeat: // ←
            state.previous()
        case 124 where !event.isARepeat: // →
            state.next()
        default:
            break
        }
    }
}

/// Borderless panels can't become key by default; this one must, to receive
/// keys. Losing key status (Cmd-Tab, a click on another display) dismisses it,
/// since keys would no longer reach it.
private final class FullscreenPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Void)?
    var onDismiss: (() -> Void)?

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        // Above the menu bar and its status items.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        backgroundColor = .clear   // the frosted background shows what's behind
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }

    // Take every key here, before the responder chain: nothing in the view
    // reads keys, and anything left unhandled there beeps. App-level event
    // monitors (the modifier taps) still see them first.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            onKeyDown?(event)
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }
}
