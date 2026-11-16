import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramMediaUtils
import TelegramUtils

public extension Message {
    var replyMarkup:ReplyMarkupMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? ReplyMarkupMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var effectAttribute: EffectMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? EffectMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var hasComments: Bool {
        if let peer = self.peers[self.id.peerId] as? TelegramChannel {
            switch peer.info {
            case let .broadcast(info):
                return info.flags.contains(.hasDiscussionGroup)
            default:
                break
            }
        }
        return false
    }
    
    var isExpiredStory: Bool {
        if let media = media.first as? TelegramMediaStory, let data = associatedStories[media.storyId] {
            return data.get(Stories.StoredItem.self) == nil
        }
        return false
    }
    var isExpiredReplyStory: Bool {
        if let reply = self.storyAttribute, let data = associatedStories[reply.storyId] {
            return data.get(Stories.StoredItem.self) == nil
        }
        return false
    }
    
    func translationAttribute(toLang: String) -> TranslationMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? TranslationMessageAttribute, attr.toLang == toLang {
                return attr
            }
        }
        return nil
    }
    
    
    func hasTranslationAttribute(toLang: String) -> Bool {
        for attr in attributes {
            if let attr = attr as? TranslationMessageAttribute, attr.toLang == toLang {
                if let poll = self.media.first as? TelegramMediaPoll {
                    if poll.results.solution != nil {
                        return attr.pollSolution != nil
                    }
                }
                return true
            }
        }
        return false
    }
    
    var isMediaSpoilered: Bool {
        for attr in attributes {
            if attr is MediaSpoilerMessageAttribute {
                return true
            }
        }
        return false
    }
    
    var hasExtendedMedia: Bool {
        if let media = self.media.first as? TelegramMediaInvoice {
            return media.extendedMedia != nil
        }
        return false
    }
    
    var consumableContent: ConsumableContentMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? ConsumableContentMessageAttribute {
                return attr
            }
        }
        return nil
    }
    var consumableMention: ConsumablePersonalMentionMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? ConsumablePersonalMentionMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var entities:[MessageTextEntity] {
        return self.textEntities?.entities ?? []
    }
    
    var audioTranscription:AudioTranscriptionMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? AudioTranscriptionMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var isImported: Bool {
        if let forwardInfo = self.forwardInfo, forwardInfo.flags.contains(.isImported) {
            return true
        }
        return false
    }
    func hasRestrictedContent(_ contentSettings: ContentSettings?) -> Bool {
        #if APP_STORE || DEBUG
        for attr in attributes {
            if let attr = attr as? RestrictedContentMessageAttribute {
                for rule in attr.rules {
                    if rule.appliesTo(platform: "ios", contentSettings: contentSettings ?? .default) || rule.appliesTo(platform: "macos", contentSettings: contentSettings ?? .default) {
                        return true
                    }
                }
            }
        }
        #endif
       
        return false
    }
    func restrictedText(_ contentSettings: ContentSettings?, contentConfig: ContentSettingsConfiguration = .default) -> String? {
        for attr in attributes {
            if let attr = attr as? RestrictedContentMessageAttribute, let contentSettings {
                for rule in attr.rules {
                    if rule.appliesTo(platform: "ios", contentSettings: contentSettings) {
                        if !contentSettings.ignoreContentRestrictionReasons.contains(rule.reason) {
                            if rule.reason != "sensitive" && !contentConfig.canAdjustSensitiveContent {
                                return rule.text
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    var file: TelegramMediaFile? {
        if let file = self.anyMedia as? TelegramMediaFile {
            return file
        } else if let webpage = self.anyMedia as? TelegramMediaWebpage {
            switch webpage.content {
            case let .Loaded(content):
                return content.file
            default:
                break
            }
        }
        return nil
    }
    var image: TelegramMediaImage? {
        if let image = self.anyMedia as? TelegramMediaImage {
            return image
        }
        return nil
    }
    
    var textEntities: TextEntitiesMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? TextEntitiesMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var autoclearTimeout: AutoclearTimeoutMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? AutoclearTimeoutMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var isAnonymousMessage: Bool {
        if let author = self.author as? TelegramChannel, sourceReference == nil, self.id.peerId == author.id {
            return true
        } else {
            return false
        }
    }
    
    var threadAttr: ReplyThreadMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? ReplyThreadMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var isAnonymousInStarReaction: Bool {
        if let attribute = self.reactionsAttribute, let myReactions = attribute.topPeers.first(where: { $0.isMy }) {
            return myReactions.isAnonymous
        } else {
            return false
        }
    }
    
    var extendedMedia: Media? {
        if let media = self.media.first as? TelegramMediaInvoice {
            if let extended = media.extendedMedia {
                switch extended {
                case let .full(media):
                    return media
                default:
                    break
                }
            }
        }
        return media.first
    }

    
    
    
    
    func effectiveReactions(_ accountPeerId: PeerId, isTags: Bool) -> ReactionsMessageAttribute? {
        return mergedMessageReactions(attributes: self.attributes, isTags: isTags)
    }
    
    func isCrosspostFromChannel(account: Account) -> Bool {
        
        var sourceReference: SourceReferenceMessageAttribute?
        for attribute in self.attributes {
            if let attribute = attribute as? SourceReferenceMessageAttribute {
                sourceReference = attribute
                break
            }
        }
        
        var isCrosspostFromChannel = false
        if let _ = sourceReference {
            if self.id.peerId != account.peerId {
                isCrosspostFromChannel = true
            }
        }

        return isCrosspostFromChannel
    }
    
    var channelViewsCount: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? ViewCountMessageAttribute {
                return Int32(attribute.count)
            }
        }
        return nil
    }
    
    var isScheduledMessage: Bool {
        return self.id.namespace == Namespaces.Message.ScheduledCloud || self.id.namespace == Namespaces.Message.ScheduledLocal
    }
    
    var wasScheduled: Bool {
        for attr in attributes {
            if attr is OutgoingScheduleInfoMessageAttribute {
                return true
            }
        }
        return self.flags.contains(.WasScheduled)
    }
    
    var isPublicPoll: Bool {
        if let media = self.anyMedia as? TelegramMediaPoll {
            return media.publicity == .public
        }
        return false
    }
    
    var isHasInlineKeyboard: Bool {
        return replyMarkup?.flags.contains(.inline) ?? false
    }
    
    
    func chatPeer(_ accountPeerId: PeerId) -> Peer? {
        var _peer: Peer?
        if let _ = adAttribute {
            return author
        }
       
        if self.id.peerId == verifyCodePeerId {
            return forwardInfo?.author ?? author
        }
        
        for attr in attributes {
            if let source = attr as? SourceReferenceMessageAttribute {
                if let info = forwardInfo {
                    if let peer = peers[source.messageId.peerId], peer is TelegramChannel, accountPeerId != id.peerId, TelegramUtilsHooks.shared.repliesPeerId() != id.peerId {
                        _peer = peer
                    } else {
                        _peer = info.author
                    }
                }
                break
            }
        }
        
        
        if let peer = coreMessageMainPeer(self) as? TelegramChannel, case .broadcast(_) = peer.info {
            _peer = author ?? peer
        } else if let author = effectiveAuthor, _peer == nil {
            if author is TelegramSecretChat {
                return coreMessageMainPeer(self)
            } else {
                _peer = author
            }
        }
        return _peer
    }
    
    var replyAttribute: ReplyMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? ReplyMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var suggestPostAttribute: SuggestedPostMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? SuggestedPostMessageAttribute {
                return attr
            }
        }
        return nil
    }
    var summarizeAttribute: SummarizationMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? SummarizationMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var publishedSuggestedPostMessageAttribute: PublishedSuggestedPostMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? PublishedSuggestedPostMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    
    var quoteAttribute: QuotedReplyMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? QuotedReplyMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var boostAttribute: BoostCountMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? BoostCountMessageAttribute {
                return attr
            }
        }
        return nil
    }
    
    var storyAttribute: ReplyStoryAttribute? {
        for attr in attributes {
            if let attr = attr as? ReplyStoryAttribute {
                return attr
            }
        }
        return nil
    }
    
    var editedAttribute: EditedMessageAttribute? {
        for attr in attributes {
            if let attr = attr as? EditedMessageAttribute, !attr.isHidden {
                return attr
            }
        }
        return nil
    }
    
    
    var hasInlineAttribute: Bool {
        for attribute in attributes {
            if let _ = attribute as? InlineBotMessageAttribute {
                return true
            }
        }
        return false
    }
    
    var inlinePeer:Peer? {
        for attribute in attributes {
            if let attribute = attribute as? InlineBotMessageAttribute, let peerId = attribute.peerId {
                return peers[peerId]
            }
        }
        if let peer = coreMessageMainPeer(self), peer.isBot {
            return peer
        }
        return nil
    }
    
    /// The media driving this message in a media-tag-filtered list, matching `predicate`. For a normal
    /// message this filters `media`; for a rich message (empty `media`, carrying a
    /// `RichTextMessageAttribute`) the media lives inside the instant page (`effectiveMedia`).
    func sharedMediaMatching(_ predicate: (Media) -> Bool) -> [Media] {
        return self.effectiveMedia.filter(predicate)
    }

    func withUpdatedStableId(_ stableId:UInt32) -> Message {
        return Message(stableId: stableId, stableVersion: stableVersion, id: id, globallyUniqueId: globallyUniqueId, groupingKey: groupingKey, groupInfo: groupInfo, threadId: threadId, timestamp: timestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, customTags: [], forwardInfo: forwardInfo, author: author, text: text, attributes: attributes, media: media, peers: peers, associatedMessages: associatedMessages, associatedMessageIds: associatedMessageIds, associatedMedia: self.associatedMedia, associatedThreadInfo: self.associatedThreadInfo, associatedStories: self.associatedStories)
    }
    func withUpdatedId(_ messageId:MessageId) -> Message {
        return Message(stableId: stableId, stableVersion: stableVersion, id: messageId, globallyUniqueId: globallyUniqueId, groupingKey: groupingKey, groupInfo: groupInfo, threadId: threadId, timestamp: timestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, customTags: [], forwardInfo: forwardInfo, author: author, text: text, attributes: attributes, media: media, peers: peers, associatedMessages: associatedMessages, associatedMessageIds: associatedMessageIds, associatedMedia: self.associatedMedia, associatedThreadInfo: self.associatedThreadInfo, associatedStories: self.associatedStories)
    }
    
    func withUpdatedGroupingKey(_ groupingKey:Int64?) -> Message {
        return Message(stableId: stableId, stableVersion: stableVersion, id: id, globallyUniqueId: globallyUniqueId, groupingKey: groupingKey, groupInfo: groupInfo, threadId: threadId, timestamp: timestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, customTags: [], forwardInfo: forwardInfo, author: author, text: text, attributes: attributes, media: media, peers: peers, associatedMessages: associatedMessages, associatedMessageIds: associatedMessageIds, associatedMedia: self.associatedMedia, associatedThreadInfo: self.associatedThreadInfo, associatedStories: self.associatedStories)
    }
    
    func withUpdatedReplyMarkupAttribute(_ attribute:ReplyMarkupMessageAttribute) -> Message {
        
        var attributes = self.attributes
        attributes.removeAll(where: { $0 is ReplyMarkupMessageAttribute})
        attributes.append(attribute)
        
        return Message(stableId: stableId, stableVersion: stableVersion, id: id, globallyUniqueId: globallyUniqueId, groupingKey: groupingKey, groupInfo: groupInfo, threadId: threadId, timestamp: timestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, customTags: [], forwardInfo: forwardInfo, author: author, text: text, attributes: attributes, media: media, peers: peers, associatedMessages: associatedMessages, associatedMessageIds: associatedMessageIds, associatedMedia: self.associatedMedia, associatedThreadInfo: self.associatedThreadInfo, associatedStories: self.associatedStories)
    }
    
    
    
    
    
    convenience init(_ media: Media, stableId: UInt32, messageId: MessageId, timestamp: Int32 = 0) {
        self.init(stableId: stableId, stableVersion: 0, id: messageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: timestamp, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "", attributes: [], media: [media], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }
}
