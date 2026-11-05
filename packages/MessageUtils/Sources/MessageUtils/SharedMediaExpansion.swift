import Foundation
import Postbox
import TelegramCore

public func sharedMediaPredicate(for tags: MessageTags) -> (Media) -> Bool {
    if tags.contains(.photoOrVideo) {
        return { media in
            if media is TelegramMediaImage { return true }
            if let file = media as? TelegramMediaFile { return file.isVideo && !file.isInstantVideo && !file.isAnimated }
            return false
        }
    } else if tags.contains(.gif) {
        return { media in (media as? TelegramMediaFile).map { $0.isAnimated && $0.isVideo } ?? false }
    } else if tags.contains(.music) {
        return { ($0 as? TelegramMediaFile)?.isMusic ?? false }
    } else if tags.contains(.voiceOrInstantVideo) {
        return { media in (media as? TelegramMediaFile).map { $0.isVoice || $0.isInstantVideo } ?? false }
    } else if tags.contains(.file) {
        return { media in
            guard let file = media as? TelegramMediaFile else { return false }
            return !file.isVideo && !file.isMusic && !file.isVoice && !file.isInstantVideo && !file.isAnimated && !file.isSticker
        }
    } else if tags.contains(.webPage) {
        return { $0 is TelegramMediaWebpage }
    }
    return { _ in true }
}

private let richSharedMediaNamespaceBase: Int32 = 0x0010_0000

public func isExpandedSharedMediaMessageId(_ id: MessageId) -> Bool {
    return id.namespace >= richSharedMediaNamespaceBase
}

public func sharedMediaDisplayPrecedes(_ lhs: MessageIndex, _ rhs: MessageIndex) -> Bool {
    if lhs.timestamp != rhs.timestamp {
        return lhs.timestamp > rhs.timestamp
    }
    let lhsExpanded = lhs.id.namespace >= richSharedMediaNamespaceBase
    let rhsExpanded = rhs.id.namespace >= richSharedMediaNamespaceBase
    if !lhsExpanded && !rhsExpanded {
        return rhs < lhs
    }
    if lhs.id.id != rhs.id.id {
        return lhs.id.id > rhs.id.id
    }
    return lhs.id.namespace < rhs.id.namespace
}

public func expandSharedMediaMessages(_ messages: [Message], where predicate: (Media) -> Bool, reverseMedia: Bool = false) -> [Message] {
    var result: [Message] = []
    for message in messages {
        guard message.media.isEmpty, message.richText != nil else {
            result.append(message)
            continue
        }
        var medias = message.sharedMediaMatching(predicate)
        if reverseMedia {
            medias.reverse()
        }
        for (index, media) in medias.enumerated() {
            var synthetic = message.withUpdatedMedia([media])
            if index > 0 {
                let id = MessageId(peerId: message.id.peerId, namespace: richSharedMediaNamespaceBase &+ Int32(index), id: message.id.id)
                let stableId: UInt32 = 0x8000_0000 | (UInt32(truncatingIfNeeded: index) << 24) | (message.stableId & 0x00FF_FFFF)
                synthetic = synthetic.withUpdatedId(id).withUpdatedStableId(stableId)
            }
            result.append(synthetic)
        }
    }
    return result
}
