import SwiftUI

/// 不绘制加载提示，但保留分页末尾的视图节点，让其 task 继续触发。
struct LoadingTaskAnchor: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
