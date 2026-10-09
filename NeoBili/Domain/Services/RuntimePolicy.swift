import Foundation

enum RuntimePolicy {
    static var isRegression: Bool {
        #if NEOBILI_REGRESSION
        true
        #else
        false
        #endif
    }
}
