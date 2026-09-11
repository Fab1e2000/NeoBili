import Foundation

enum LiveRoomLinkParser {
    /// Accept room numbers and official room links, including links embedded in
    /// the text copied from Bilibili's share sheet. This performs no networking.
    static func roomID(from text: String) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.allSatisfy(\.isASCII), input.allSatisfy(\.isNumber),
           let id = Int(input), id > 0 { return id }

        let pattern = #"(?i)(?:https?://)?live\.bilibili\.com/(?:blanc/|h5/)?([0-9]+)(?=$|[/?#\s\p{P}])"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let fullRange = Range(match.range, in: input),
              let idRange = Range(match.range(at: 1), in: input),
              let id = Int(input[idRange]), id > 0 else { return nil }
        // A suffix such as evil-live.bilibili.com is not an official hostname.
        if fullRange.lowerBound > input.startIndex {
            let preceding = input[input.index(before: fullRange.lowerBound)]
            if preceding.isASCII && (preceding.isLetter || preceding.isNumber || ".-_/".contains(preceding)) {
                return nil
            }
        }
        return id
    }
}
