import AppKit
import ApplicationServices

/// Watches global keyboard events and detects "solo taps" of modifier keys
/// (a modifier pressed and released with no other key in between), reporting the
/// bound action. Requires Accessibility permission to receive keyboard events.
@MainActor
final class HotkeyMonitor {
    /// Called when a modifier key is tapped by itself (pressed and released with
    /// no other key involved).
    var onTap: @MainActor (ModifierKey) -> Void = { _ in }
    /// When it returns true, incoming events are ignored (e.g. while recording).
    var isSuspended: @MainActor () -> Bool = { false }

    /// Max time a modifier may be held and still count as a tap.
    private let holdThreshold: TimeInterval = 0.5

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trustTimer: Timer?

    // Solo-tap state
    private var candidate: ModifierKey?
    private var candidateDownTime: TimeInterval = 0
    private var candidateValid = false

    // MARK: Accessibility

    static var isTrusted: Bool { AXIsProcessTrusted() }

    func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Lifecycle

    func start() {
        if Self.isTrusted {
            installMonitors()
        } else {
            promptForAccessibility()
            // Poll until the user grants access, then install monitors.
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
                MainActor.assumeIsolated {
                    guard let self else { t.invalidate(); return }
                    if Self.isTrusted {
                        self.installMonitors()
                        t.invalidate()
                        self.trustTimer = nil
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            trustTimer = timer
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil
        localMonitor = nil
        trustTimer?.invalidate()
        trustTimer = nil
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    // MARK: Event handling

    private func handle(_ event: NSEvent) {
        if isSuspended() { return }
        switch event.type {
        case .flagsChanged: handleFlagsChanged(event)
        case .keyDown:       candidateValid = false   // a real key => any modifier hold is a combo
        default: break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard let mk = ModifierKey.from(keyCode: event.keyCode) else {
            // Non-monitored modifier changed (fn, caps lock, …) => cancel candidate.
            candidateValid = false
            return
        }

        // Determine down/up from the guaranteed device-independent flag, and the
        // exact left/right key from the event's keyCode.
        let di = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isDown = di.contains(mk.flag)

        if isDown {
            // A tap must be solo: no other modifier type held at press time.
            if di.subtracting(mk.flag).isEmpty {
                candidate = mk
                candidateDownTime = event.timestamp
                candidateValid = true
            } else {
                candidate = nil
                candidateValid = false
            }
        } else if candidate == mk {
            let held = event.timestamp - candidateDownTime
            if candidateValid && held <= holdThreshold {
                onTap(mk)
            }
            candidate = nil
            candidateValid = false
        }
    }
}
