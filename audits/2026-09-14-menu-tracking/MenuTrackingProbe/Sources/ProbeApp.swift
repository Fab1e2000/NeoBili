import SwiftUI

@main
struct ProbeApp: App {
    var body: some Scene { WindowGroup { ProbeRoot() } }
}

@Observable @MainActor
final class ProbeClock {
    var position = 0.0
}

struct ProbeRoot: View {
    @State private var clock = ProbeClock()
    @State private var selection = "none"
    private let updates = !ProcessInfo.processInfo.arguments.contains("--paused")
    private let isolate = ProcessInfo.processInfo.arguments.contains("--isolate")

    var body: some View {
        VStack(spacing: 16) {
            Text("Menu tracking probe")
            Text("\(updates ? "10 Hz" : "Paused") / \(isolate ? "isolated" : "original")")
            ProbeOverlay(position: clock.position, selection: $selection, isolate: isolate)
                .frame(height: 230)
                .background(Color(white: 0.12))
            Text(selection).accessibilityIdentifier("probe.selection")
            Text(String(format: "%.1f", clock.position)).accessibilityIdentifier("probe.clock")
            Spacer()
        }
        .padding(.top, 24)
        .preferredColorScheme(.dark)
        .task {
            guard updates else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                clock.position += 0.1
            }
        }
    }
}

// Diagnostic control: only this wrapper's equality boundary changes between
// runs. The original chrome source, glass, menu labels and callbacks are shared.
struct FrozenChrome<Content: View>: View, Equatable {
    let content: Content
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View { content }
}

struct ProbeOverlay: View {
    let position: Double
    @Binding var selection: String
    let isolate: Bool
    @State private var keepsControlsForMenu = false

    var body: some View {
        if isolate { FrozenChrome(content: chrome).equatable() }
        else { chrome }
    }

    private var chrome: some View {
        PlayerGlassChrome(
            videoQualityControl: quality("分辨率", title: "1080P", prefix: "video",
                                         options: ["360P", "720P", "1080P"]),
            audioQualityControl: quality("音质", title: "Hi-Res", prefix: "audio",
                                         options: ["Standard", "Hi-Res", "Dolby"]),
            position: position, duration: 600, buffered: position + 10,
            isPlaying: true,
            onMenuInteraction: { keepsControlsForMenu = true }
        ) {
            Button("Watch later") { selection = "more-selected" }
            Button("Sleep timer") { selection = "sleep-selected" }
            Button("Other option") { selection = "other-selected" }
        }
    }

    private func quality(_ label: String, title: String, prefix: String,
                         options: [String]) -> PlayerQualityControl {
        PlayerQualityControl(title: title, accessibilityLabel: label,
            options: options.enumerated().map { .init(id: $0.offset, title: $0.element) },
            selectedID: 2, isEnabled: true,
            onSelect: { selection = "\(prefix)-\($0)" })
    }
}
