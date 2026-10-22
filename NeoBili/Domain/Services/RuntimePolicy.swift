import Foundation

public enum RuntimePolicy {
    public static var isRegression: Bool {
        #if NEOBILI_REGRESSION
        true
        #else
        false
        #endif
    }
}
