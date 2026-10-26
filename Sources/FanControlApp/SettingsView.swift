import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("Chung", systemImage: "gearshape") }
        }
        .frame(width: 820, height: 500)
    }
}
