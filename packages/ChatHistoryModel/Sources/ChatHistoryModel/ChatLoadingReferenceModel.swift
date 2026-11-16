import AppKit
import SwiftSignalKit
import InlineStickerLayer
import TGUIKit
import TelegramCore
import MessageTextUtils
import TelegramContext
import TelegramTheme

public enum ChatReferenceAvailability: Equatable {
    case available
    case loading
    case unavailable

    public static func resolve(hasContent: Bool, referencesPending: Bool) -> ChatReferenceAvailability {
        return hasContent ? .available : referencesPending ? .loading : .unavailable
    }
}

public enum ChatReferenceSkeleton {
    public static func frames(size: CGSize, leftInset: CGFloat = 8, story: Bool, hasQuote: Bool) -> [CGRect] {
        guard size.width.isFinite, size.height.isFinite, size.width > leftInset + 4, size.height > 0 else { return [] }
        let tileSide = story ? min(30, max(0, size.height - 8)) : 0
        let textX = leftInset + (story ? tileSide + 6 : 0)
        let width = max(0, size.width - textX - 6)
        var frames: [CGRect] = []
        if story { frames.append(CGRect(x: leftInset, y: 4, width: tileSide, height: tileSide)) }
        if width > 0 {
            frames.append(CGRect(x: textX, y: 5, width: min(80, width * 0.6), height: min(7, size.height)))
            if !hasQuote { frames.append(CGRect(x: textX, y: min(23, max(0, size.height - 7)), width: min(140, width), height: min(7, size.height))) }
        }
        return frames.map { $0.intersection(CGRect(origin: .zero, size: size)) }.filter { !$0.isEmpty && !$0.isNull }
    }

    public static func image(size: CGSize, leftInset: CGFloat = 8, story: Bool, hasQuote: Bool) -> CGImage? {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1, size.width <= 4096, size.height <= 4096,
              let context = CGContext(data: nil, width: Int(ceil(size.width * 2)), height: Int(ceil(size.height * 2)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: 2, y: 2)
        context.setFillColor(NSColor.white.cgColor)
        for frame in frames(size: size, leftInset: leftInset, story: story, hasQuote: hasQuote) {
            context.addPath(CGPath(roundedRect: frame, cornerWidth: 3, cornerHeight: 3, transform: nil)); context.fillPath()
        }
        return context.makeImage()
    }
}

public final class ChatLoadingReferenceModel: ChatAccessoryModel {
    private let story: Bool
    private let quote: EngineMessageReplyQuote?
    private let displaysQuote: Bool
    private var skeleton: CGImage?

    public init(context: any AccountContextProtocol, story: Bool, quote: EngineMessageReplyQuote? = nil, presentation: ChatAccessoryPresentation? = nil) {
        self.story = story
        self.quote = quote
        self.displaysQuote = quote.map { !messageReplyQuoteText($0).text.isEmpty } ?? false
        super.init(context: context, presentation: presentation, drawLine: true)
        self.header = TextViewLayout(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.clear]), maximumNumberOfLines: 1)
        if let quote, displaysQuote {
            let value = messageReplyQuoteText(quote)
            let text = ChatHistoryModelHooks.shared.applyMessageEntities([TextEntitiesMessageAttribute(entities: value.entities)], value.text, nil, context, 13, { _, _, _, _ in }, self.presentation.enabledText, self.presentation.enabledText, self.presentation.enabledText, self.presentation.enabledText, self.presentation.app.dark, self.presentation.app.bubbled).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: text, associatedMedia: [:], entities: value.entities, isPremium: context.isPremium, ignoreSpoiler: true)
            self.message = TextViewLayout(text, maximumNumberOfLines: 8)
        } else {
            self.message = TextViewLayout(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.clear]), maximumNumberOfLines: 1)
        }
        self.nodeReady.set(.single(true))
    }

    public override var mediaInset: CGFloat { story ? 36 : 0 }
    public override var quoteIcon: CGImage? { quote == nil ? nil : presentation.quoteIcon }
    public override var shimm: (NSPoint, CGImage?) { (.zero, skeleton) }

    public override func measureSize(_ width: CGFloat = 0, sizeToFit: Bool = false) {
        super.measureSize(width, sizeToFit: sizeToFit)
        if sizeToFit { self.size.width = min(max(0, width), max(self.size.width, story ? 190 : 160)) }
        skeleton = ChatReferenceSkeleton.image(size: self.size, leftInset: self.leftInset, story: story, hasQuote: displaysQuote)
    }
}
