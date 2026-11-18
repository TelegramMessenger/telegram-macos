import Foundation
import Postbox
import TelegramCore
import MessageUtils
import TelegramUtils

private func mediaBreaksBubbleMerge(_ media: Media) -> Bool {
    if let story = media as? TelegramMediaStory {
        return story.isMention
    }
    if let file = media as? TelegramMediaFile {
        for attribute in file.attributes {
            switch attribute {
            case .Sticker:
                return false
            case let .Video(_, _, flags, _, _, _):
                if flags.contains(.instantRoundVideo) {
                    return true
                }
            default:
                break
            }
        }
        return false
    }
    return media is TelegramMediaAction || media is TelegramMediaExpiredContent
}

private func bubbleMergeAuthorId(_ message: Message, useRawAuthor: Bool) -> PeerId? {
    if useRawAuthor {
        return message.author?.id
    }
    var authorId = message.author?.id
    for attribute in message.attributes {
        if let attribute = attribute as? SourceReferenceMessageAttribute {
            if message.id.peerId == TelegramUtilsHooks.shared.repliesPeerId() {
                authorId = message.forwardInfo?.author?.id ?? authorId
            } else {
                authorId = message.peers[attribute.messageId.peerId]?.id
            }
            break
        }
    }
    if let originalAuthor = message.sourceAuthorInfo?.originalAuthor {
        authorId = message.peers[originalAuthor]?.id
    }
    return authorId
}

private func anonymousAdminSignature(_ message: Message, authorId: PeerId?) -> String? {
    guard let channel = message.peers[message.id.peerId] as? TelegramChannel, case .group = channel.info, authorId == channel.id else {
        return nil
    }
    if let signature = message.authorSignatureAttribute?.signature, !signature.isEmpty {
        return signature
    }
    return nil
}

private func isEphemeralOrWelcome(_ message: Message) -> Bool {
    return Namespaces.Message.allEphemeral.contains(message.id.namespace) || Namespaces.Message.allWelcomeMessages.contains(message.id.namespace)
}

public func shouldMergeBubbles(upper: Message, lower: Message, accountPeerId: PeerId) -> Bool {
    if isEphemeralOrWelcome(upper) != isEphemeralOrWelcome(lower) {
        return false
    }

    let upperChannel = upper.peers[upper.id.peerId] as? TelegramChannel
    var useRawAuthors = false
    if let upperChannel, case let .broadcast(info) = upperChannel.info {
        useRawAuthors = info.flags.contains(.messagesShouldHaveProfiles)
    }
    let upperAuthorId = bubbleMergeAuthorId(upper, useRawAuthor: useRawAuthors)
    let lowerAuthorId = bubbleMergeAuthorId(lower, useRawAuthor: useRawAuthors)
    let upperIncoming = upper.effectivelyIncoming(accountPeerId)

    var sameAuthor = upperAuthorId == lowerAuthorId && upperIncoming == lower.effectivelyIncoming(accountPeerId)

    let upperSource = upper.sourceAuthorInfo
    let lowerSource = lower.sourceAuthorInfo
    if let upperSource, let lowerSource {
        if upperSource.originalAuthor != lowerSource.originalAuthor || upperSource.originalAuthorName != lowerSource.originalAuthorName {
            sameAuthor = false
        }
    } else if (upperSource == nil) != (lowerSource == nil) {
        sameAuthor = false
    }

    if sameAuthor, anonymousAdminSignature(upper, authorId: upperAuthorId) != anonymousAdminSignature(lower, authorId: lowerAuthorId) {
        sameAuthor = false
    }

    var upperTimestamp = upper.timestamp
    var lowerTimestamp = lower.timestamp
    if let upperForward = upper.forwardInfo, upperForward.flags.contains(.isImported), let lowerForward = lower.forwardInfo, lowerForward.flags.contains(.isImported) {
        upperTimestamp = upperForward.date
        lowerTimestamp = lowerForward.date
        if (upperForward.author != nil) == (lowerForward.author != nil) && (upperForward.authorSignature != nil) == (lowerForward.authorSignature != nil) {
            if let upperAuthor = upperForward.author, let lowerAuthor = lowerForward.author {
                sameAuthor = upperAuthor.id == lowerAuthor.id
            } else if let upperSignature = upperForward.authorSignature, let lowerSignature = lowerForward.authorSignature {
                sameAuthor = upperSignature == lowerSignature
            }
        } else {
            sameAuthor = false
        }
    }

    var isPaid = upper.paidStarsAttribute != nil && lower.paidStarsAttribute != nil
    if isPaid, upperChannel?.flags.contains(.isMonoforum) == true {
        isPaid = false
    }

    let isWelcomePair = Namespaces.Message.allWelcomeMessages.contains(upper.id.namespace) && Namespaces.Message.allWelcomeMessages.contains(lower.id.namespace)
    guard (isWelcomePair || abs(upperTimestamp - lowerTimestamp) < simpleDif), upper.id.peerId == lower.id.peerId, sameAuthor, !isPaid else {
        return false
    }

    if let upperChannel, case .group = upperChannel.info, upperAuthorId == upperChannel.id, !upperIncoming {
        return false
    }
    if let markup = upper.replyMarkup, markup.flags.contains(.inline), !markup.rows.isEmpty {
        return false
    }
    return !upper.media.contains(where: mediaBreaksBubbleMerge) && !lower.media.contains(where: mediaBreaksBubbleMerge)
}
