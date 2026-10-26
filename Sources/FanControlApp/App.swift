import SwiftUI

@main
struct FanControlMain: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Cài đặt Fan Control", id: "settings") {
            SettingsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
    }
}
