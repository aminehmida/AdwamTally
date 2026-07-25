import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState.shared
    private var monitor: HotkeyMonitor?
    private var overlay: OverlayController?

    /// On the increment key: single tap = +1, double tap = next dhikr. We hold a
    /// pending +1 briefly to see whether a second tap arrives.
    private let doubleTapWindow: TimeInterval = 0.28
    private var pendingIncrement: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayController(state: state)

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

        if let pending = pendingIncrement {
            // Second tap within the window → it's a double tap → next dhikr.
            pending.cancel()
            pendingIncrement = nil
            state.next()
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.pendingIncrement = nil
                self?.state.increment()
            }
            pendingIncrement = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
        }
    }

    private func dispatch(_ action: CounterAction) {
        switch action {
        case .increment:    state.increment()
        case .next:         state.next()
        case .previous:     state.previous()
        case .resetCurrent: state.resetCurrent()
        }
    }
}
