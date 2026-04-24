import SwiftUI

struct MenuContentView: View {
    @Environment(MenuBarModel.self) private var menuBarModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interface: \(menuBarModel.interfaceDisplayName)")
            Divider()
            
            Section {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .fixedSize()
    }
}
