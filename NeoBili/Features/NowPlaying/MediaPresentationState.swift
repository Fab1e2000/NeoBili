import Foundation

/// SwiftUI owns modal lifetime. This state only selects its destination and the
/// view supplying the geometry for the single, stable native zoom transition.
struct MediaPresentationState {
    enum Destination: String, Identifiable {
        case player
        var id: Self { self }
    }

    enum Source: Hashable {
        case player
        case content(String)

        var nativeID: AnyHashable {
            switch self {
            case .player: AnyHashable(self)
            case .content(let id): AnyHashable(id)
            }
        }
    }

    var destination: Destination?
    private(set) var entrySourceID = ""
    private(set) var activeSourceID = ""

    mutating func prepareSource(_ id: String) {
        entrySourceID = id
        activeSourceID = id
    }

    mutating func completeEntrance(returningTo id: String) {
        guard destination != nil else { return }
        activeSourceID = id
    }

    func source(for id: String) -> Source {
        id == activeSourceID ? .player : .content(id)
    }
}
