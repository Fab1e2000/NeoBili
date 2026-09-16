import SwiftUI
import UIKit

struct MiniPlayerMovementSettingsView: View {
    @AppStorage(MiniPlayerMovementSettings.topKey) private var top = 0.0
    @AppStorage(MiniPlayerMovementSettings.bottomKey) private var bottom = 1.0
    @State private var editing = false
    private var limits: (top: Double, bottom: Double) {
        MiniPlayerMovementSettings.normalized(top: top, bottom: bottom)
    }

    var body: some View {
        Form {
            Section("可移动区域") {
                boundary("上边界", value: Binding(get: { limits.top }, set: { top = $0; preview() }),
                         range: 0...(limits.bottom - MiniPlayerMovementSettings.minimumSpan))
                boundary("下边界", value: Binding(get: { limits.bottom }, set: { bottom = $0; preview() }),
                         range: (limits.top + MiniPlayerMovementSettings.minimumSpan)...1)
                Button("恢复默认范围") { top = 0; bottom = 1; preview() }
            }
        }
        .navigationTitle("小窗移动范围")
        .navigationBarTitleDisplayMode(.inline)
        .leftEdgeTapDeadZone()
        .onDisappear { MiniPlayerBoundsPreviewState.shared.hide() }
    }

    private func boundary(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 10) {
            LabeledContent(title, value: "\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
            Slider(value: value, in: range, step: 0.01) { active in
                editing = active
                preview()
            }
            .accessibilityLabel(title)
            .accessibilityValue("\(Int((value.wrappedValue * 100).rounded()))%")
        }
    }

    private func preview() {
        MiniPlayerBoundsPreviewState.shared.show(holding: editing)
    }
}

@MainActor
@Observable
final class MiniPlayerBoundsPreviewState {
    static let shared = MiniPlayerBoundsPreviewState()
    var isVisible = false
    private var hideTask: Task<Void, Never>?

    func show(holding: Bool) {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { isVisible = true }
        guard !holding else { return }
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(.easeIn(duration: 0.45)) { isVisible = false }
    }
}

/// Uses the same host/safe-area coordinate system as the moving player.
struct MiniPlayerBoundsPreview: UIViewRepresentable {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    let top: Double
    let bottom: Double
    func makeUIView(context: Context) -> BoundsView { BoundsView() }
    func updateUIView(_ view: BoundsView, context: Context) {
        view.top = top
        view.bottom = bottom
        view.tintColor = UIColor(AppTheme.selected(themeID).color)
        view.setNeedsDisplay()
    }

    final class BoundsView: UIView {
        var top = 0.0
        var bottom = 1.0
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() { super.layoutSubviews(); setNeedsDisplay() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsDisplay() }
        override func draw(_ rect: CGRect) {
            let area = MiniPlayerLayout.movementBounds(in: safeAreaLayoutGuide.layoutFrame.insetBy(dx: 12, dy: 12),
                                                       top: top, bottom: bottom)
            tintColor.withAlphaComponent(0.22).setFill()
            UIBezierPath(rect: area).fill()
            tintColor.withAlphaComponent(0.85).setFill()
            UIBezierPath(rect: CGRect(x: area.minX, y: area.minY, width: area.width, height: 1.5)).fill()
            UIBezierPath(rect: CGRect(x: area.minX, y: area.maxY - 1.5, width: area.width, height: 1.5)).fill()
        }
    }
}
