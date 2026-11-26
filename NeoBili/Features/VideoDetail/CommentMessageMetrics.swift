import NeoBiliCore
import NeoBiliDomain
import SwiftUI
import UIKit

/// Inputs affecting line breaks. The image URL's loading state is irrelevant
/// because both the placeholder and the rendered bitmap occupy the same square.
struct CommentMessageMetrics: Hashable, Sendable {
    let message: String
    let emotes: [String: CommentEmote]
    let links: [String: CommentJumpLink]
    let size: DynamicTypeSize
    let scale: CGFloat
    let includesTimes: Bool
    let bold: Bool

    var locale = Locale.current
    var direction = LayoutDirection.leftToRight

    private struct Key: Hashable, Sendable {
        let metrics: CommentMessageMetrics
        let width: CGFloat
    }
    private static let cache = ImageMemoryCache<Key, Bool>(maximumBytes: 2 * 1024 * 1024, maximumEntries: 512)

    private struct HeightKey: Hashable, Sendable {
        let text: Key
        let expanded: Bool
    }
    private static let heights = ImageMemoryCache<HeightKey, CGFloat>(maximumBytes: 2 * 1024 * 1024, maximumEntries: 512)

    func bodyHeight(width: CGFloat, expanded: Bool, measure: () -> CGFloat) -> CGFloat {
        let key = HeightKey(text: Key(metrics: self, width: width), expanded: expanded)
        if let height = Self.heights.value(for: key) { return height }
        let height = measure()
        Self.heights.insert(height, for: key, cost: message.utf8.count + 128)
        return height
    }

    var buttonHeight: CGFloat {
        ceil(CommentEmoteText.scaledFont(textStyle: .caption, typeSize: size).lineHeight)
    }

    func canExpand(at width: CGFloat) -> Bool {
        guard width > 0, width.isFinite else { return false }
        let key = Key(metrics: self, width: width)
        if let result = Self.cache.value(for: key) { return result }
        let font = CommentEmoteText.scaledFont(textStyle: .subheadline, typeSize: size)
        let text = NSMutableAttributedString()
        func append(_ string: String) {
            let displayed = CommentLinks.attributed(string, metadata: links, includesTimes: includesTimes)
            text.append(NSAttributedString(string: String(displayed.characters)))
        }
        for segment in CommentEmoteSegments.prepared(message: message, emotes: emotes) {
            switch segment {
            case .text(let string): append(string)
            case .emote(let literal, let emote):
                guard emote.secureURL != nil else { append(literal); continue }
                let side = CommentEmoteText.emoteHeight(for: emote, font: font)
                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(x: 0, y: (font.descender * 0.5).rounded(), width: side, height: side)
                text.append(NSAttributedString(attachment: attachment))
            }
        }
        let face: UIFont
        if bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            face = UIFont(descriptor: descriptor, size: font.pointSize)
        } else {
            face = font
        }
        text.addAttribute(.font, value: face, range: NSRange(location: 0, length: text.length))
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = CommentLayout.collapsedMessageLines + 1
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let range = manager.glyphRange(for: container)
        var lines = manager.extraLineFragmentTextContainer == nil ? 0 : 1
        manager.enumerateLineFragments(forGlyphRange: range) { _, _, _, _, _ in lines += 1 }
        let result = lines > CommentLayout.collapsedMessageLines
        Self.cache.insert(result, for: key, cost: message.utf8.count + 128)
        return result
    }
}
