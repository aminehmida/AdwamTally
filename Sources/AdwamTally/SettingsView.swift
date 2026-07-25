import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            CountersTab(state: state)
                .tabItem { Label("Counters", systemImage: "list.number") }
            KeysTab(state: state)
                .tabItem { Label("Keys", systemImage: "keyboard") }
            AppearanceTab(state: state)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - Counters

private struct CountersTab: View {
    @ObservedObject var state: AppState
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(Array(state.counters.enumerated()), id: \.element.id) { _, counter in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: counter.colorHex))
                                .frame(width: 11, height: 11)
                                .opacity(counter.enabled ? 1 : 0.35)
                            Text(counter.label.isEmpty ? "Untitled" : counter.label)
                                .lineLimit(1)
                                .foregroundStyle(counter.enabled ? .primary : .secondary)
                            Spacer()
                            Text(subtitle(counter))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Toggle("", isOn: enabledBinding(counter.id))
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.mini)
                                .help(counter.enabled ? "Enabled — tap to skip in rotation" : "Disabled")
                        }
                        .tag(counter.id)
                    }
                    .onMove { indices, dest in
                        state.counters.move(fromOffsets: indices, toOffset: dest)
                    }
                }
                Divider()
                HStack {
                    Button {
                        let new = Counter(label: "New dhikr", colorHex: randomHex())
                        state.counters.append(new)
                        selection = new.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        removeSelected()
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 200)

            Group {
                if let binding = selectedBinding {
                    CounterDetail(counter: binding)
                } else {
                    Text("Select a counter to edit")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 260)
        }
    }

    private var selectedBinding: Binding<Counter>? {
        guard let id = selection,
              let idx = state.counters.firstIndex(where: { $0.id == id }) else { return nil }
        return $state.counters[idx]
    }

    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { state.counters.first(where: { $0.id == id })?.enabled ?? true },
            set: { state.setEnabled(id, $0) }
        )
    }

    private func removeSelected() {
        guard let id = selection,
              let idx = state.counters.firstIndex(where: { $0.id == id }) else { return }
        state.counters.remove(at: idx)
        selection = state.counters.first?.id
        if state.activeIndex >= state.counters.count {
            state.activeIndex = max(0, state.counters.count - 1)
        }
    }

    private func subtitle(_ c: Counter) -> String {
        if let t = c.target, t > 0 { return "\(c.count)/\(t)" }
        return "\(c.count)"
    }

    private func randomHex() -> String {
        let palette = ["#34C759", "#4C8DFF", "#FF9F0A", "#FF375F", "#AF52DE", "#5AC8FA", "#FFD60A"]
        return palette[state.counters.count % palette.count]
    }
}

private struct CounterDetail: View {
    @Binding var counter: Counter

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $counter.enabled)
                TextField("Label", text: $counter.label)
                    .environment(\.layoutDirection, counter.isRTL ? .rightToLeft : .leftToRight)
                Toggle("Right-to-left (Arabic)", isOn: $counter.isRTL)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            } footer: {
                if !counter.enabled {
                    Text("Disabled — skipped when tapping through counters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Target") {
                Toggle("Has target", isOn: hasTargetBinding)
                if counter.hasTarget {
                    Stepper(value: targetBinding, in: 1...100000) {
                        HStack {
                            Text("Target")
                            Spacer()
                            TextField("", value: targetBinding, format: .number)
                                .frame(width: 70)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Toggle("Auto-advance to next when reached", isOn: $counter.autoAdvance)
                    Picker("When reached", selection: $counter.afterTarget) {
                        ForEach(AfterTarget.allCases) { Text($0.displayName).tag($0) }
                    }
                }
            }

            Section {
                HStack {
                    Text("Current count")
                    Spacer()
                    Text("\(counter.count)")
                        .foregroundStyle(.secondary)
                    Button("Reset") { counter.count = 0 }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: counter.colorHex) },
            set: { counter.colorHex = NSColor($0).toHex }
        )
    }

    private var hasTargetBinding: Binding<Bool> {
        Binding(
            get: { counter.hasTarget },
            set: { on in counter.target = on ? (counter.target ?? 33) : nil }
        )
    }

    private var targetBinding: Binding<Int> {
        Binding(
            get: { counter.target ?? 33 },
            set: { counter.target = max(1, $0) }
        )
    }
}

// MARK: - Keys

private struct KeysTab: View {
    @ObservedObject var state: AppState
    @State private var recordingAction: CounterAction?
    @State private var recorderMonitor: Any?

    var body: some View {
        Form {
            Section {
                ForEach(CounterAction.allCases) { action in
                    HStack {
                        Text(action.displayName)
                        Spacer()
                        Text(keyLabel(action))
                            .foregroundStyle(recordingAction == action ? Color.accentColor : .secondary)
                            .frame(minWidth: 120, alignment: .trailing)
                        Button(recordingAction == action ? "Press a modifier…" : "Record") {
                            startRecording(action)
                        }
                        Button {
                            state.settings.bindings[action] = nil
                        } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.borderless)
                            .disabled(state.settings.bindings[action] == nil)
                    }
                }
            } header: {
                Text("Tap a modifier key by itself to trigger an action.")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Single-tap the Increment key to add 1; double-tap it to move to the next dhikr.")
                    Text("Only bare taps count — using a key as part of a shortcut (e.g. ⌘C) is ignored. Requires Accessibility permission.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    private func keyLabel(_ action: CounterAction) -> String {
        if let mk = state.settings.bindings[action] {
            return "\(mk.symbol) \(mk.displayName)"
        }
        return "Not set"
    }

    private func startRecording(_ action: CounterAction) {
        stopRecording()
        recordingAction = action
        state.suspendHotkeys = true
        recorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            if let mk = ModifierKey.from(keyCode: event.keyCode),
               event.modifierFlags.contains(mk.flag) {
                assign(mk, to: action)
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        if let m = recorderMonitor { NSEvent.removeMonitor(m) }
        recorderMonitor = nil
        recordingAction = nil
        state.suspendHotkeys = false
    }

    private func assign(_ mk: ModifierKey, to action: CounterAction) {
        for (act, key) in state.settings.bindings where key == mk && act != action {
            state.settings.bindings[act] = nil
        }
        state.settings.bindings[action] = mk
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @ObservedObject var state: AppState

    private let sounds = ["Tink", "Pop", "Glass", "Ping", "Purr", "Submarine", "Funk", "Morse"]

    var body: some View {
        Form {
            Section("Popup") {
                Picker("Size", selection: $state.settings.popupSize) {
                    ForEach(PopupSize.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Position")
                    PositionGrid(selection: $state.settings.popupPosition)
                }

                HStack {
                    Text("Auto-hide after")
                    Slider(value: $state.settings.autoHideSeconds, in: 1...10, step: 0.5)
                    Text("\(state.settings.autoHideSeconds, specifier: "%.1f")s")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                HStack {
                    Text("Background opacity")
                    Slider(value: $state.settings.backgroundOpacity, in: 0.15...1.0, step: 0.05)
                    Text("\(Int(state.settings.backgroundOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }

                Toggle("Border", isOn: $state.settings.showBorder)

                Toggle("Islamic pattern background", isOn: $state.settings.showPattern)
                if state.settings.showPattern {
                    HStack {
                        Text("Pattern intensity")
                        Slider(value: $state.settings.patternOpacity, in: 0...0.4, step: 0.01)
                        Text("\(Int(state.settings.patternOpacity / 0.4 * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Completion") {
                Toggle("Play chime when target reached", isOn: $state.settings.chimeEnabled)
                Picker("Sound", selection: $state.settings.chimeName) {
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!state.settings.chimeEnabled)
                Button("Test sound") { NSSound(named: state.settings.chimeName)?.play() }
                    .disabled(!state.settings.chimeEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PositionGrid: View {
    @Binding var selection: PopupPosition

    private let rows: [[PopupPosition]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, .center, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row) { pos in
                        Button {
                            selection = pos
                        } label: {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == pos ? Color.accentColor : Color.secondary.opacity(0.18))
                                .frame(width: 44, height: 30)
                                .overlay(
                                    Circle()
                                        .fill(selection == pos ? Color.white : Color.secondary)
                                        .frame(width: 7, height: 7)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(pos.displayName)
                    }
                }
            }
        }
    }
}
