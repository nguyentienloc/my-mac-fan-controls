import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CurvesTab()
                .tabItem { Label("Đường cong", systemImage: "chart.xyaxis.line") }
            GeneralTab()
                .tabItem { Label("Chung", systemImage: "gearshape") }
        }
        .frame(width: 820, height: 500)
    }
}
