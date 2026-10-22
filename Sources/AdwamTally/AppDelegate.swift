import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState.shared
    private var monitor: HotkeyMonitor?
    private var overlay: OverlayController?
    private var fullscreen: FullscreenController?

    /// On the increment key: single tap = +1, double tap = next dhikr, triple
    /// tap = toggle full screen (each gesture can be turned off). While one is
    /// enabled, taps are held briefly to see whether another one follows.
    private let multiTapWindow: TimeInterval = 0.28
    private var pendingTaps = 0
    private var pendingTapAction: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayController(state: state)
        fullscreen = FullscreenController(state: state)

        let m = HotkeyMonitor()
        m.onTap = { [weak self] key in self?.handleTap(key) }
        m.isSuspended = { [weak self] in self?.state.suspendHotkeys ?? false }
        m.start()
        monitor = m
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.saveNow()
    }

    private func handleTap(_ key: ModifierKey) {
        guard let action = state.settings.action(for: key) else { return }

        // The count key gets single/double-tap treatment; other keys fire now.
        guard action == .increment else {
            dispatch(action)
            return
        }

        let settings = state.settings
        let maxTaps = settings.tripleTapFullscreen ? 3 : settings.doubleTapNext ? 2 : 1
        pendingTapAction?.cancel()
        pendingTaps += 1
        if pendingTaps >= maxTaps {
            // Nothing can follow the longest enabled gesture, so act right away.
            commitPendingTaps()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.commitPendingTaps()
        }
        pendingTapAction = work
        DispatchQueue.main.asyncAfter(deadline: .now() + multiTapWindow, execute: work)
    }

    /// Acts on the taps gathered so far: as a gesture if that one is enabled,
    /// otherwise as +1 each.
    private func commitPendingTaps() {
        let taps = pendingTaps
        pendingTaps = 0
        pendingTapAction?.cancel()
        pendingTapAction = nil
        if taps == 3 && state.settings.tripleTapFullscreen {
            fullscreen?.toggle()
        } else if taps == 2 && state.settings.doubleTapNext {
            state.next()
        } else {
            for _ in 0..<taps { state.increment() }
        }
    }

    private func dispatch(_ action: CounterAction) {
        switch action {
        case .increment:    state.increment()
        case .next:         state.next()
        case .previous:     state.previous()
        case .resetCurrent: state.resetCurrent()
        case .toggleFullscreen: fullscreen?.toggle()
        }
    }
}
