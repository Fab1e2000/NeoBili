import SwiftUI
import UIKit

/// 全屏内容忽略安全区后，仍从所在 UIWindow 获取刘海、圆角与 Home 指示条的实际避让距离。
struct PlayerSafeAreaReader: UIViewRepresentable {
    let onChange: (EdgeInsets) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.scheduleReport()
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        view.onChange = nil
    }

    @MainActor
    final class ObserverView: UIView {
        var onChange: ((EdgeInsets) -> Void)?
        private var lastReported: UIEdgeInsets?
        private var reportPending = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleReport()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleReport()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            scheduleReport()
        }

        func scheduleReport() {
            guard let window, window.safeAreaInsets != lastReported, !reportPending else { return }
            reportPending = true
            // 布局和 SwiftUI update 回调可能在同一帧触发多次；下一轮读取最终窗口边距。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportPending = false
                guard let window = self.window, self.onChange != nil else { return }
                let insets = window.safeAreaInsets
                guard self.lastReported != insets else { return }
                self.lastReported = insets
                self.onChange?(EdgeInsets(top: insets.top, leading: insets.left,
                                          bottom: insets.bottom, trailing: insets.right))
            }
        }
    }
}
