import SwiftUI

extension View {
    func settingsPage(_ title: LocalizedStringKey) -> some View {
        leftEdgeTapDeadZone()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
