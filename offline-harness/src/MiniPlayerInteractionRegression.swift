import Foundation

/// Native presentation selection and asymmetric source handoff, without a UI.
@main
struct MiniPlayerInteractionRegression {
    static func main() {
        let mini = "mini"
        var state = MediaPresentationState()

        // Open from a card. Exactly that source supplies the fixed player key.
        state.prepareSource("card")
        state.destination = .player
        precondition(state.source(for: "card") == .player)
        precondition(state.source(for: mini) == .content(mini))

        // Entrance completion moves the source, not the transition or modal item.
        let destination = state.destination
        state.completeEntrance(returningTo: mini)
        precondition(state.destination == destination)
        precondition(state.entrySourceID == "card")
        precondition(state.source(for: mini) == .player)
        precondition(state.source(for: "card") == .content("card"))

        // Close during entrance: a late appearance cannot move the exit target.
        state.prepareSource("early-card")
        state.destination = .player
        state.destination = nil
        state.completeEntrance(returningTo: mini)
        precondition(state.source(for: "early-card") == .player)
        precondition(state.destination == nil)

        // Expand from the mini bar using the same fixed transition key.
        state.prepareSource(mini)
        state.destination = .player
        precondition(state.source(for: mini) == .player)
        state.completeEntrance(returningTo: mini)
        precondition(state.source(for: mini) == .player)

        // Cancelling an interactive return restores the destination and source.
        state.destination = nil
        state.destination = .player
        state.completeEntrance(returningTo: mini)
        precondition(state.destination == .player && state.source(for: mini) == .player)

        // Closing after cancelling still wins; no completion reopens the page.
        state.destination = nil
        state.completeEntrance(returningTo: mini)
        precondition(state.destination == nil)

        // A new video takes the single source role; the previous entry loses it.
        state.prepareSource("next-card")
        state.destination = .player
        precondition(state.source(for: "next-card") == .player)
        precondition(state.source(for: mini) == .content(mini))
        precondition(state.source(for: "card") == .content("card"))

        // Cell reuse cannot attach the previous video's source to new content.
        precondition(state.source(for: "reused-card") == .content("reused-card"))
        state.completeEntrance(returningTo: mini)
        precondition(state.source(for: "next-card") == .content("next-card"))
        precondition(state.source(for: mini) == .player)

        // Non-player detail pages share this modifier and retain their String IDs.
        let dynamic = "following-dynamic-1"
        precondition(state.source(for: dynamic).nativeID == AnyHashable(dynamic))
        precondition(state.source(for: mini).nativeID == AnyHashable(MediaPresentationState.Source.player))

        print("Native mini-player presentation: 9 regression scenarios passed")
    }
}
