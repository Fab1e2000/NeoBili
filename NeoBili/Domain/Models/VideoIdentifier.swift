import Foundation

enum VideoIdentifier {
    static func bvid(aid: Int) -> String? {
        guard aid > 0, aid < (1 << 51) else { return nil }
        let alphabet = Array("FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf")
        var result = Array("BV1000000000")
        var value = ((1 << 51) | aid) ^ 23442827791579
        var index = result.count - 1
        while value > 0 {
            result[index] = alphabet[value % 58]
            value /= 58
            index -= 1
        }
        result.swapAt(3, 9)
        result.swapAt(4, 7)
        return String(result)
    }
}
