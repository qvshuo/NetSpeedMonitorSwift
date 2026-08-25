import SwiftUI

@main
struct NetSpeedMonitorApp: App {
    @State private var menuBarModel = MenuBarModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(menuBarModel)
        } label: {
            Image(nsImage: menuBarModel.currentIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}
