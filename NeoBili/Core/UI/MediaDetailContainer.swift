import SwiftUI

/// 视频和直播简介共用的普通填充容器，颜色与合集、分 P 入口保持一致。
extension View {
    func mediaDetailContainer() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
