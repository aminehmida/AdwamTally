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
    private var dailyResetTimer: Timer?

    /// When the last +1 happened; nil once the counts have been cleared for a
    /// new day (nothing left to reset).
    private var lastCountAt: Date?

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
            lastCountAt = state.lastCountAt
        } else {
            counters = Defaults.counters()
            activeIndex = 0
            settings = AppSettings()
        }

        // Persist any change (counter edits, settings) shortly after it happens.
        autosave = objectWillChange.sink { [weak self] in
            self?.scheduleSave()
        }

        // Catch a midnight that passed while the app was closed, then keep
        // checking — a minute's granularity also covers sleep/wake and clock
        // changes without extra bookkeeping.
        resetIfNewDay()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetIfNewDay() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dailyResetTimer = timer
    }

    // MARK: Derived

    var active: Counter? {
        counters.indices.contains(activeIndex) ? counters[activeIndex] : nil
    }

    // MARK: User actions

    func increment() {
        resetIfNewDay()
        lastCountAt = Date()
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

    // MARK: Daily reset

    /// Clears all counts once a new day has started. A midnight crossed
    /// mid-session is skipped: if the last count fell between 23:00 and
    /// midnight, the reset waits for the following midnight so a late session
    /// isn't interrupted. Silent — the overlay isn't shown for it.
    func resetIfNewDay(now: Date = Date()) {
        guard settings.resetAfterMidnight, let last = lastCountAt else { return }
        let cal = Calendar.current
        guard let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) else { return }
        let lateSession = cal.component(.hour, from: last) >= 23
        let due = lateSession ? (cal.date(byAdding: .day, value: 1, to: midnight) ?? midnight) : midnight
        guard now >= due else { return }

        advanceWorkItem?.cancel()
        advanceWorkItem = nil
        pendingAdvance = false
        for i in counters.indices { counters[i].count = 0 }
        activeIndex = 0
        ensureActiveEnabled()
        lastCountAt = nil
        scheduleSave()
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
        let state = PersistedState(counters: counters, activeIndex: activeIndex, settings: settings,
                                   lastCountAt: lastCountAt)
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = Self.stateURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
