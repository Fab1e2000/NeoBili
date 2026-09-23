import SwiftUI

extension View {
    func settingsPage(_ title: String) -> some View {
        leftEdgeTapDeadZone()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
