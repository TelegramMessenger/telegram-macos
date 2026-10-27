import Foundation

protocol Media {}
enum TelegramMediaActionType {
    case topicCreated(title: String, iconColor: Int32, iconFileId: Int64?)
    case topicEdited
    case joinedChannel
}
struct TelegramMediaAction: Media {
    let action: TelegramMediaActionType
}
struct TelegramMediaGiveawayResults: Media {}
struct TelegramMediaStory: Media {}
struct MessageId {
    let id: Int32
}
struct Message {
    let threadId: Int64?
    let media: [Media]
}
struct ReplyMessageAttribute {
    let messageId: MessageId
    let isQuote: Bool
}

func showsReply(threadId: Int64?, message: Message, attribute: ReplyMessageAttribute, replyMessage: Message) -> Bool {
    __REPLY_POLICY__
    return !ignore
}

let topic = TelegramMediaAction(action: .topicCreated(title: "Example topic", iconColor: 0, iconFileId: nil))
var checks = 0
var failures = 0

func expect(_ name: String, visible: Bool, currentThread: Int64? = nil, messageThread: Int64? = 10, replyId: Int32 = 10, replyMedia: [Media] = [], quote: Bool = false, messageMedia: [Media] = []) {
    checks += 1
    let actual = showsReply(
        threadId: currentThread,
        message: Message(threadId: messageThread, media: messageMedia),
        attribute: ReplyMessageAttribute(messageId: MessageId(id: replyId), isQuote: quote),
        replyMessage: Message(threadId: messageThread, media: replyMedia)
    )
    if actual != visible {
        failures += 1
        print("FAIL: \(name): expected visible=\(visible), got \(actual)")
    }
}

expect("overview omits topic-creation association", visible: false, replyMedia: [topic])
expect("topic-creation preview is independent of current thread", visible: false, currentThread: 20, replyMedia: [topic])
expect("selected topic keeps root suppression", visible: false, currentThread: 10, replyMedia: [topic])
expect("overview preserves explicit topic quote", visible: true, replyMedia: [topic], quote: true)
expect("different thread preserves explicit topic quote", visible: true, currentThread: 20, replyMedia: [topic], quote: true)
expect("selected topic preserves existing quoted-root suppression", visible: false, currentThread: 10, replyMedia: [topic], quote: true)
expect("overview preserves ordinary replies", visible: true)
expect("selected topic preserves replies to other messages", visible: true, currentThread: 10, replyId: 11)
expect("non-topic replies remain visible", visible: true, messageThread: nil)
expect("ordinary explicit quotes remain visible", visible: true, quote: true)
expect("topic edits remain visible", visible: true, replyMedia: [TelegramMediaAction(action: .topicEdited)])
expect("other service replies remain visible", visible: true, replyMedia: [TelegramMediaAction(action: .joinedChannel)])
expect("story replies reach their existing renderer", visible: true, replyMedia: [TelegramMediaStory()])
expect("selected discussion root keeps suppression", visible: false, currentThread: 10)
expect("giveaway results keep suppression", visible: false, messageMedia: [TelegramMediaGiveawayResults()])
expect("quoted giveaway results keep suppression", visible: false, quote: true, messageMedia: [TelegramMediaGiveawayResults()])

print("\(checks - failures)/\(checks) reply policy checks passed")
exit(failures == 0 ? 0 : 1)
