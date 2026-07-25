import SwiftUI

@main
struct AdwamTallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Label(menuBarTitle, systemImage: "circle.hexagongrid")
        }

        Settings {
            SettingsView(state: state)
        }
    }

    private var menuBarTitle: String {
        if let c = state.active { return "\(c.count)" }
        return "–"
    }
}
