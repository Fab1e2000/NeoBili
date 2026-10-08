import SwiftUI

extension EnvironmentValues {
    /// A hierarchy may replace services without changing other windows or tests.
    @Entry var applicationServices: ApplicationServices = .live
}
