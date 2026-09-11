import Foundation
import CoreGraphics

@main
enum PlayerSurfaceAspectRegression {
    static func main() {
        precondition(PlayerSurfaceGeometry.displayAspectRatio(16.0 / 9, rotation: 90) == 9.0 / 16)
        precondition(PlayerSurfaceGeometry.displayAspectRatio(16.0 / 9, rotation: -90) == 9.0 / 16)
        precondition(PlayerSurfaceGeometry.displayAspectRatio(.nan, rotation: 0) == nil)
        let surface = CGSize(width: 874, height: 402)
        for ratio in [9.0 / 16, 1, 4.0 / 3, 16.0 / 9, 2.4, 3.0] {
            for container in [CGSize(width: 402, height: min(402 / ratio, 560)), CGSize(width: 402, height: 226), CGSize(width: 402, height: 874), surface] {
                let scale = PlayerSurfaceGeometry.presentationScale(
                    surfaceSize: surface, containerSize: container, videoAspectRatio: ratio
                )
                let width = min(surface.width, surface.height * ratio) * scale
                let height = width / ratio
                precondition(width <= container.width + 0.000_001)
                precondition(height <= container.height + 0.000_001)
                precondition(abs(width - container.width) < 0.000_001 || abs(height - container.height) < 0.000_001)
            }
        }
        print("Player surface aspect regression checks passed (24 layouts + rotation)")
    }
}
