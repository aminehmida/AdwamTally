import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let c = state.active {
            Text(currentLine(c))
        }

        let enabled = state.counters.filter { $0.enabled }
        if !enabled.isEmpty {
            Divider()
            ForEach(enabled) { counter in
                Button {
                    state.select(id: counter.id)
                } label: {
                    Text(rowLine(counter, active: counter.id == state.active?.id))
                }
            }
        }

        Divider()
        Button("Reset Current") { state.resetCurrent() }
            .disabled(state.active == nil)
        Button("Reset All") { state.resetAll() }

        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit Adwam Tally") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func currentLine(_ c: Counter) -> String {
        if let t = c.target, t > 0 { return "Current: \(c.label)  \(c.count)/\(t)" }
        return "Current: \(c.label)  \(c.count)"
    }

    private func rowLine(_ c: Counter, active: Bool) -> String {
        let mark = active ? "● " : "   "
        if let t = c.target, t > 0 { return "\(mark)\(c.label)  (\(c.count)/\(t))" }
        return "\(mark)\(c.label)  (\(c.count))"
    }
}
