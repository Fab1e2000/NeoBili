import Foundation
import SwiftUI

// MARK: - 十六进制颜色

extension Color {
    /// SC 服务端下发 `#RRGGBB` 色串；解析失败返回 nil 由调用方给默认值。
    init?(hex: String?) {
        guard var value = hex, value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xFF) / 255,
                  green: Double((number >> 8) & 0xFF) / 255,
                  blue: Double(number & 0xFF) / 255)
    }
}
