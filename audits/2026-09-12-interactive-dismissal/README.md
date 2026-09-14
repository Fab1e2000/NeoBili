# Interactive video dismissal — 2026-09-12

Changes: freeze collapse input/momentum and playback-layout phase from UIKit interactive dismissal start; restore page ownership and clear dismissal state on cancellation; keep vertical content pans with scrolling regardless of collapse distance; avoid installing gesture delegates after recognition begins; forward both root and service-sheet presentation lifecycle events.

Validation: generic iOS build-for-testing passed, no Simulator. Physical iPhone 17: 22 MiniPlayerTests (including two new cancellation regressions) and 3 PlayerInteractionRefinementTests passed. Combined run's single native-zoom geometry fixture failed its last-sampled-frame horizontal distance assertion (105pt vs 45pt). A focused rerun with geometry attachment passed without changing that assertion or production code. Timing-sensitive sampling remains a limitation; this is not evidence of reproducing the user's intermittent physical finger gesture. Geometry tests exercise programmatic UIKit dismissal, state tests exercise cancellation state transitions.

Results: combined-tests.json retains the initial failure; geometry-recheck.json records the focused rerun. Raw bundles: /tmp/NeoBiliGestureCancel-20260912.xcresult and /tmp/NeoBiliGestureGeometry-20260912.xcresult.
