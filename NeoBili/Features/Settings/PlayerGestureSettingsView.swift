import SwiftUI

struct PlayerGestureSettingsView: View {
    var body: some View {
        Form { PlayerGestureSettingsSection() }
            .settingsPage("播放器手势")
    }
}
