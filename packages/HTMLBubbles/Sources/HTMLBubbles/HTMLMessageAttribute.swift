import Foundation
import Postbox

public final class HTMLMessageAttribute: MessageAttribute {
    public let state: HTMLBubbleState

    public init(state: HTMLBubbleState) {
        self.state = state
    }

    public init(decoder: PostboxDecoder) {
        self.state = HTMLBubbleState(html: decoder.decodeStringForKey("h", orElse: ""), outgoing: decoder.decodeInt32ForKey("o", orElse: 0) != 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(state.source, forKey: "h")
        encoder.encodeInt32(state.outgoing ? 1 : 0, forKey: "o")
    }
}

public extension Message {
    var htmlBubbleState: HTMLBubbleState? {
        for attribute in attributes {
            if let attribute = attribute as? HTMLMessageAttribute {
                return attribute.state
            }
        }
        return nil
    }
}
