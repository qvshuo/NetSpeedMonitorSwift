import SwiftUI

struct MenuContentView: View {
    @Environment(MenuBarModel.self) private var menuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if menuBarModel.presentation.samplingFailed {
                Text("Network data unavailable")
            }
            Text("Interface: \(menuBarModel.interfaceDisplayName)")
            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .fixedSize()
    }
}
