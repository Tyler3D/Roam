import SwiftUI

/// Time estimates MVP: placeholder screen — feature not built yet.
struct TimeEstimatesPlaceholderView: View {
    @Environment(AuthManager.self) private var authManager
    @Binding var showDebugMenu: Bool

    var body: some View {
        ContentUnavailableView(
            "Coming Soon",
            systemImage: "clock",
            description: Text("Time estimates MVP — feature not built yet.")
        )
        .navigationTitle("Time Estimates")
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showDebugMenu = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
            }
            #endif
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    authManager.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }
}
