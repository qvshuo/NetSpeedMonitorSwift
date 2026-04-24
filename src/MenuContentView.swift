import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var menuBarState: MenuBarState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interface: \(menuBarState.monitoredInterfaceName)")
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
