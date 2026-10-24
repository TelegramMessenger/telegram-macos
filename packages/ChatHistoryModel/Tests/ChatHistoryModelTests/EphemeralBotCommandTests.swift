import Foundation
import XCTest
import Postbox
@testable import TelegramCore
@testable import ChatHistoryModel

final class EphemeralBotCommandTests: XCTestCase {
    private let firstId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let secondId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let chatId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(3))

    private func command(_ name: String, botId: PeerId, username: String?, ephemeral: Bool) -> PeerCommand {
        let peer = TelegramUser(id: botId, accessHash: nil, firstName: "Bot", lastName: nil, username: username, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        return PeerCommand(peer: EnginePeer(peer), command: BotCommand(text: name, description: name, isEphemeral: ephemeral))
    }

    private func message(_ text: String, entities: [MessageTextEntity] = []) -> EnqueueMessage {
        return .message(text: text, attributes: [TextEntitiesMessageAttribute(entities: entities)], inlineStickers: [:], mediaReference: nil, threadId: 42, replyToMessageId: EngineMessageReplySubject(messageId: MessageId(peerId: chatId, namespace: Namespaces.Message.Cloud, id: 7), quote: nil, innerSubject: nil), replyToStoryId: nil, localGroupingKey: nil, correlationId: 11, bubbleUpEmojiOrStickersets: [])
    }

    func testResolvesOnlyAdvertisedEphemeralCommands() {
        let commands = PeerCommands(commands: [
            command("secret", botId: firstId, username: "WhisperBot", ephemeral: true),
            command("help", botId: firstId, username: "WhisperBot", ephemeral: false),
        ])
        XCTAssertEqual(resolveEphemeralBotCommand(text: "/secret", peerCommands: commands)?.botPeerId, firstId)
        XCTAssertEqual(resolveEphemeralBotCommand(text: "/secret@wHiSpErBoT argument", peerCommands: commands)?.botPeerId, firstId)
        for text in ["/help", "/missing", "/secret@OtherBot", "/secret@", "/secret!", "before /secret", "/", "//secret", "/secret😀"] {
            XCTAssertNil(resolveEphemeralBotCommand(text: text, peerCommands: commands), text)
        }
    }

    func testAmbiguousBareCommandDoesNotChooseAnotherBot() {
        let commands = PeerCommands(commands: [
            command("secret", botId: firstId, username: "FirstBot", ephemeral: true),
            command("secret", botId: secondId, username: "SecondBot", ephemeral: false),
        ])
        XCTAssertNil(resolveEphemeralBotCommand(text: "/secret", peerCommands: commands))
        XCTAssertEqual(resolveEphemeralBotCommand(text: "/secret@FirstBot", peerCommands: commands)?.botPeerId, firstId)
        XCTAssertNil(resolveEphemeralBotCommand(text: "/secret@SecondBot", peerCommands: commands))
    }

    func testArgumentsFormattingReplyAndTopicSurviveRouting() throws {
        let text = "/secret@WhisperBot 😀 аргумент\nsecond line"
        let bold = MessageTextEntity(range: 21 ..< 29, type: .Bold)
        let resolved = ephemeralBotCommand(botPeerId: firstId, text: text)
        let messages = resolved.apply(to: [message(text, entities: [bold])])
        guard case let .message(sentText, attributes, _, _, threadId, reply, _, _, correlationId, _) = try XCTUnwrap(messages.first) else {
            return XCTFail("Expected a text message")
        }
        XCTAssertEqual(sentText, text)
        XCTAssertEqual(threadId, 42)
        XCTAssertEqual(reply?.messageId.id, 7)
        XCTAssertEqual(correlationId, 11)
        let outgoing = try XCTUnwrap(attributes.compactMap { $0 as? EphemeralOutgoingMessageAttribute }.first)
        XCTAssertEqual(outgoing.botPeerId, firstId)
        XCTAssertEqual(outgoing.randomId, 0)
        XCTAssertEqual(outgoing.state, .sending)
        let entities = try XCTUnwrap(attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first).entities
        XCTAssertTrue(entities.contains(bold))
        XCTAssertEqual(entities.first, MessageTextEntity(range: 0 ..< 18, type: .BotCommand))
    }

    func testEveryChunkRemainsPrivateWithoutRepeatingCommandEntity() throws {
        let resolved = ephemeralBotCommand(botPeerId: firstId, text: "/secret argument")
        let messages = resolved.apply(to: [message("/secret " + String(repeating: "x", count: 4088)), message("remaining arguments")])
        for (index, message) in messages.enumerated() {
            guard case let .message(_, attributes, _, _, _, _, _, _, _, _) = message else {
                return XCTFail("Expected a text message")
            }
            let outgoing = attributes.compactMap { $0 as? EphemeralOutgoingMessageAttribute }
            XCTAssertEqual(outgoing.count, 1)
            XCTAssertEqual(outgoing.first?.botPeerId, firstId)
            let entities = try XCTUnwrap(attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first).entities
            XCTAssertEqual(entities.filter { $0.type == .BotCommand }.count, index == 0 ? 1 : 0)
        }
    }

    func testSelectedCommandDoesNotRequireCachedUsernameOrCommandList() throws {
        let resolved = ephemeralBotCommand(botPeerId: firstId, text: "/secret")
        guard case let .message(_, attributes, _, _, _, _, _, _, _, _) = try XCTUnwrap(resolved.apply(to: [message("/secret")]).first) else {
            return XCTFail("Expected a text message")
        }
        XCTAssertEqual(attributes.compactMap { $0 as? EphemeralOutgoingMessageAttribute }.first?.botPeerId, firstId)
    }

    func testExistingCommandEntityIsNotDuplicated() throws {
        let entity = MessageTextEntity(range: 0 ..< 7, type: .BotCommand)
        let resolved = ephemeralBotCommand(botPeerId: firstId, text: "/secret argument")
        guard case let .message(_, attributes, _, _, _, _, _, _, _, _) = try XCTUnwrap(resolved.apply(to: [message("/secret argument", entities: [entity])]).first) else {
            return XCTFail("Expected a text message")
        }
        XCTAssertEqual(attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.first?.entities, [entity])
    }

    func testForwardIsNotConvertedToEphemeralMessage() throws {
        let source = MessageId(peerId: chatId, namespace: Namespaces.Message.Cloud, id: 10)
        let forward = EnqueueMessage.forward(source: source, threadId: 42, grouping: .none, attributes: [], correlationId: 11)
        let resolved = ephemeralBotCommand(botPeerId: firstId, text: "/secret")
        guard case let .forward(sentSource, threadId, _, attributes, correlationId) = try XCTUnwrap(resolved.apply(to: [forward]).first) else {
            return XCTFail("Expected a forward")
        }
        XCTAssertEqual(sentSource, source)
        XCTAssertEqual(threadId, 42)
        XCTAssertEqual(correlationId, 11)
        XCTAssertTrue(attributes.isEmpty)
    }
}
