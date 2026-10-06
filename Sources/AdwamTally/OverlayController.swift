import AppKit
import Combine
import SwiftUI

/// Owns the non-activating floating panel, positions it per the 9-grid on the
/// screen under the mouse, fades it in on each event, and auto-hides it after a
/// short idle period.
@MainActor
final class OverlayController {
    private let state: AppState
    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayView>
    private let reveal = OverlayReveal()
    private var hideTimer: Timer?
    /// Bumped on every show so a fade-out that's still in flight knows it was
    /// superseded and must not order the panel out.
    private var showGeneration = 0
    private var cancellable: AnyCancellable?

    // The card already carries transparent shadow padding, so keep this small.
    private let margin: CGFloat = 4

    init(state: AppState) {
        self.state = state

        hostingView = NSHostingView(rootView: OverlayView(state: state, reveal: reveal))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        // Keep intrinsicContentSize (so we can size the panel), but drop the
        // min/max window-size options whose "content size extrema" path throws
        // during the display cycle for a borderless panel.
        hostingView.sizingOptions = [.intrinsicContentSize]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false   // SwiftUI draws the drop shadow (see GlassCard)
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hostingView
        panel.alphaValue = 0

        // Re-show + reposition on every user-visible change.
        cancellable = state.$eventToken
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
            }
    }

    // MARK: Show / hide

    func show() {
        guard let screen = screenUnderMouse() else { return }
        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width < 1 || size.height < 1 { size = hostingView.intrinsicContentSize }
        let origin = state.settings.popupPosition.origin(for: size, in: screen, margin: margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        showGeneration &+= 1
        // Only replay the reveal when appearing from hidden; a show during the
        // fade-out (or while already up) just fades back in.
        let revealing = !panel.isVisible
        if revealing {
            panel.alphaValue = 0
            reveal.shown = false
        }
        // Always re-order front: the panel can be "visible" yet stranded on
        // another Space (e.g. after switching to a full-screen app), and
        // isVisible alone can't tell. This is idempotent when already on top.
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = revealing ? 0.3 : 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        if revealing {
            // Next runloop pass, so the collapsed state is rendered first and
            // the animation has something to start from. A long, gentle
            // ease-out with no overshoot keeps it calm.
            DispatchQueue.main.async { [reveal] in
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.45)) {
                    reveal.shown = true
                }
            }
        }
        resetHideTimer()
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        let delay = max(0.5, state.settings.autoHideSeconds)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func hide() {
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() during the fade wins; don't yank the panel away.
                guard let self, self.showGeneration == generation else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func screenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main
    }
}
