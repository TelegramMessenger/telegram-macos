import Foundation
import Postbox
import TelegramCore

struct ResolvedEphemeralBotCommand {
    let botPeerId: PeerId
    let commandLength: Int

    func apply(to messages: [EnqueueMessage]) -> [EnqueueMessage] {
        return messages.enumerated().map { index, message in
            guard case .message = message else {
                return message
            }
            return message.withUpdatedAttributes { attributes in
                var attributes = attributes
                if index == 0, commandLength > 0 {
                    let commandEntity = MessageTextEntity(range: 0 ..< commandLength, type: .BotCommand)
                    if let index = attributes.firstIndex(where: { $0 is TextEntitiesMessageAttribute }), let attribute = attributes[index] as? TextEntitiesMessageAttribute {
                        if !attribute.entities.contains(commandEntity) {
                            let entities = (attribute.entities + [commandEntity]).sorted { lhs, rhs in
                                if lhs.range.lowerBound != rhs.range.lowerBound {
                                    return lhs.range.lowerBound < rhs.range.lowerBound
                                }
                                return lhs.range.upperBound > rhs.range.upperBound
                            }
                            attributes[index] = TextEntitiesMessageAttribute(entities: entities)
                        }
                    } else {
                        attributes.append(TextEntitiesMessageAttribute(entities: [commandEntity]))
                    }
                }
                attributes.append(EphemeralOutgoingMessageAttribute(botPeerId: botPeerId, randomId: 0, state: .sending))
                return attributes
            }
        }
    }
}

private struct ParsedBotCommandToken {
    let command: String
    let botAddressName: String?
    let length: Int
}

private func isBotCommandScalar(_ value: unichar) -> Bool {
    return (48 ... 57).contains(value) || (65 ... 90).contains(value) || (97 ... 122).contains(value) || value == 95
}

private func parseFirstBotCommandToken(_ text: String) -> ParsedBotCommandToken? {
    let text = text as NSString
    guard text.length >= 2, text.character(at: 0) == 47 else {
        return nil
    }
    var index = 1
    while index < text.length, isBotCommandScalar(text.character(at: index)) {
        index += 1
    }
    guard index > 1 else {
        return nil
    }
    let command = text.substring(with: NSRange(location: 1, length: index - 1))
    var botAddressName: String?
    if index < text.length, text.character(at: index) == 64 {
        let start = index + 1
        index = start
        while index < text.length, isBotCommandScalar(text.character(at: index)) {
            index += 1
        }
        guard index > start else {
            return nil
        }
        botAddressName = text.substring(with: NSRange(location: start, length: index - start))
    }
    if index < text.length {
        guard let scalar = UnicodeScalar(Int(text.character(at: index))), CharacterSet.whitespacesAndNewlines.contains(scalar) else {
            return nil
        }
    }
    return ParsedBotCommandToken(command: command, botAddressName: botAddressName, length: index)
}

func mayContainTypedEphemeralBotCommand(_ text: String) -> Bool {
    return parseFirstBotCommandToken(text) != nil
}

func ephemeralBotCommand(botPeerId: PeerId, text: String) -> ResolvedEphemeralBotCommand {
    return ResolvedEphemeralBotCommand(botPeerId: botPeerId, commandLength: parseFirstBotCommandToken(text)?.length ?? 0)
}

func resolveEphemeralBotCommand(text: String, peerCommands: PeerCommands) -> ResolvedEphemeralBotCommand? {
    guard let parsed = parseFirstBotCommandToken(text) else {
        return nil
    }
    let matches = peerCommands.commands.filter { command in
        guard command.command.text == parsed.command else {
            return false
        }
        if let botAddressName = parsed.botAddressName {
            return command.peer.addressName?.caseInsensitiveCompare(botAddressName) == .orderedSame
        }
        return true
    }
    guard matches.count == 1, let match = matches.first, match.command.isEphemeral else {
        return nil
    }
    return ResolvedEphemeralBotCommand(botPeerId: match.peer.id, commandLength: parsed.length)
}
