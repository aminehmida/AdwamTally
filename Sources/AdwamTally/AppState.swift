import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var counters: [Counter]
    @Published var activeIndex: Int
    @Published var settings: AppSettings

    /// Bumps on every user-visible change so the overlay can show/refresh and
    /// reset its auto-hide timer.
    @Published private(set) var eventToken: Int = 0
    /// Bumps when a counter reaches its target so the overlay can pulse.
    @Published private(set) var completionToken: Int = 0

    /// When true, the global hotkey monitor ignores events (used while the user
    /// is recording a new key binding in Settings).
    @Published var suspendHotkeys = false

    /// How long the completed counter stays visible before auto-advancing.
    private let completionHold: TimeInterval = 0.8

    private var pendingAdvance = false
    private var advanceWorkItem: DispatchWorkItem?
    private var saveWorkItem: DispatchWorkItem?
    private var autosave: AnyCancellable?

    // MARK: Init / persistence

    private static var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AdwamTally/state.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.stateURL),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data),
           !state.counters.isEmpty {
            counters = state.counters
            activeIndex = min(max(0, state.activeIndex), state.counters.count - 1)
            settings = state.settings
        } else {
            counters = Defaults.counters()
            activeIndex = 0
            settings = AppSettings()
        }

        // Persist any change (counter edits, settings) shortly after it happens.
        autosave = objectWillChange.sink { [weak self] in
            self?.scheduleSave()
        }
    }

    // MARK: Derived

    var active: Counter? {
        counters.indices.contains(activeIndex) ? counters[activeIndex] : nil
    }

    // MARK: User actions

    func increment() {
        flushPendingAdvance()
        ensureActiveEnabled()
        guard counters.indices.contains(activeIndex), counters[activeIndex].enabled else { return }
        counters[activeIndex].count += 1
        let c = counters[activeIndex]

        if let t = c.target, t > 0 {
            if c.count == t {
                completionToken &+= 1
                playChimeIfEnabled()
                if c.autoAdvance {
                    scheduleAdvance()
                }
            } else if c.count > t {
                // Exceeded target while staying put (auto-advance off).
                if c.afterTarget == .resetToZero {
                    counters[activeIndex].count = 1   // begin a fresh round
                }
                // .keepCounting: leave the count climbing past the target.
            }
        }
        bump()
    }

    func next() {
        flushPendingAdvance()
        advanceIndex(by: 1)
        bump()
    }

    func previous() {
        flushPendingAdvance()
        advanceIndex(by: -1)
        bump()
    }

    func resetCurrent() {
        flushPendingAdvance()
        guard counters.indices.contains(activeIndex) else { return }
        counters[activeIndex].count = 0
        bump()
    }

    func resetAll() {
        flushPendingAdvance()
        for i in counters.indices { counters[i].count = 0 }
        activeIndex = 0
        ensureActiveEnabled()
        bump()
    }

    /// Jump directly to a counter (used from the menu / settings).
    func select(id: UUID) {
        flushPendingAdvance()
        if let idx = counters.firstIndex(where: { $0.id == id }), counters[idx].enabled {
            activeIndex = idx
            bump()
        }
    }

    /// Enable/disable a counter, keeping the active selection on an enabled one.
    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let idx = counters.firstIndex(where: { $0.id == id }) else { return }
        counters[idx].enabled = enabled
        ensureActiveEnabled()
    }

    // MARK: Auto-advance sequencing

    private func scheduleAdvance() {
        pendingAdvance = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.applyAdvance() }
        }
        advanceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + completionHold, execute: work)
    }

    private func flushPendingAdvance() {
        if pendingAdvance { applyAdvance() }
    }

    private func applyAdvance() {
        advanceWorkItem?.cancel()
        advanceWorkItem = nil
        guard pendingAdvance else { return }
        pendingAdvance = false
        if counters.indices.contains(activeIndex),
           counters[activeIndex].afterTarget == .resetToZero {
            counters[activeIndex].count = 0
        }
        advanceIndex(by: 1)
        bump()
    }

    private func advanceIndex(by delta: Int) {
        if let idx = enabledIndexStep(from: activeIndex, by: delta) {
            activeIndex = idx
        }
    }

    /// Steps from `start` in `delta` direction to the next *enabled* counter,
    /// wrapping around. Returns nil if no counter is enabled.
    private func enabledIndexStep(from start: Int, by delta: Int) -> Int? {
        guard !counters.isEmpty else { return nil }
        let n = counters.count
        var i = start
        for _ in 0..<n {
            i = ((i + delta) % n + n) % n
            if counters[i].enabled { return i }
        }
        return counters.indices.contains(start) && counters[start].enabled ? start : nil
    }

    /// If the active counter is disabled, move to the nearest enabled one.
    private func ensureActiveEnabled() {
        guard !counters.isEmpty else { return }
        guard counters.indices.contains(activeIndex) else { activeIndex = 0; return }
        if counters[activeIndex].enabled { return }
        if let idx = enabledIndexStep(from: activeIndex, by: 1) {
            activeIndex = idx
        }
    }

    // MARK: Feedback

    private func playChimeIfEnabled() {
        guard settings.chimeEnabled else { return }
        NSSound(named: settings.chimeName)?.play()
    }

    // MARK: Save

    private func bump() {
        eventToken &+= 1
        scheduleSave()
    }

    /// Call after mutating counters/settings from the settings UI.
    func settingsChanged() {
        objectWillChange.send()
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        let state = PersistedState(counters: counters, activeIndex: activeIndex, settings: settings)
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = Self.stateURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
