import XCTest
import AppKit
import Postbox
import TelegramCore
import TGUIKit
import TelegramTheme
import ColorPalette
import ThemeSettings
@testable import ChatListUI
@testable import MessageTextUtils

private struct SubmoduleDateTimeFormat {
    let groupingSeparator: String
    let decimalSeparator: String
}

private func submoduleFormatTonAmountText(_ value: Int64, dateTimeFormat: SubmoduleDateTimeFormat, showPlus: Bool = false, maxDecimalPositions: Int? = 2, formatString: ((Int32) -> String)? = nil) -> String {
    let magnitude = value.magnitude
    let integerPart = magnitude / 1_000_000_000
    let fractionalPart = magnitude % 1_000_000_000
    let decimalPositions = min(9, max(0, maxDecimalPositions ?? 9))

    let fractionalDigits = String(fractionalPart)
    let fullFractionalPart = String(repeating: "0", count: 9 - fractionalDigits.count) + fractionalDigits
    var fractionalPartString = String(fullFractionalPart.prefix(decimalPositions))
    if integerPart == 0 && magnitude != 0 && fractionalPartString.allSatisfy({ $0 == "0" }) {
        fractionalPartString = fullFractionalPart
    }
    while fractionalPartString.hasSuffix("0") {
        fractionalPartString.removeLast()
    }

    var balanceText = String(integerPart)
    if !dateTimeFormat.groupingSeparator.isEmpty {
        var groupingOffset = balanceText.count - 3
        while groupingOffset > 0 {
            balanceText.insert(contentsOf: dateTimeFormat.groupingSeparator, at: balanceText.index(balanceText.startIndex, offsetBy: groupingOffset))
            groupingOffset -= 3
        }
    }
    if !fractionalPartString.isEmpty {
        balanceText += dateTimeFormat.decimalSeparator + fractionalPartString
    }

    if value < 0 {
        balanceText.insert("-", at: balanceText.startIndex)
    } else if showPlus {
        balanceText.insert("+", at: balanceText.startIndex)
    }

    if let formatString {
        let pluralizationValue: Int32 = (integerPart == 1 && fractionalPartString.isEmpty) ? 1 : 100
        return formatString(pluralizationValue).replacingOccurrences(of: "\(pluralizationValue)", with: balanceText)
    }
    return balanceText
}

private func submoduleIncomingGramTransferPreview(message: Message, accountPeerId: PeerId, strings: [String: String], dateTimeFormat: SubmoduleDateTimeFormat, includeDiamond: Bool = false) -> String? {
    guard message.effectivelyIncoming(accountPeerId) else {
        return nil
    }
    for media in message.media {
        guard let media = media as? TelegramMediaAction, case let .gramTransfer(amount, _, _, _, _) = media.action else {
            continue
        }
        let currencyGrams: (Int32) -> String = { value in
            let format = value == 1 ? strings["Currency.Grams_1"]! : strings["Currency.Grams_any"]!
            return format.replacingOccurrences(of: "%@", with: "\(value)")
        }
        let amountText = submoduleFormatTonAmountText(amount, dateTimeFormat: dateTimeFormat, maxDecimalPositions: 3, formatString: currencyGrams)
        let prefix = includeDiamond ? "💎" : ""
        if message.id.peerId.isTelegramNotifications {
            return strings["Notification.GramTransferUnknown"]!.replacingOccurrences(of: "%@", with: prefix + amountText)
        } else {
            return strings["Notification.GramTransfer.Compact"]!.replacingOccurrences(of: "%@", with: prefix + amountText)
        }
    }
    return nil
}

private func submoduleHasUnreadIncomingGramTransfer(_ messages: [Message], combinedReadState: EnginePeerReadCounters?, accountPeerId: PeerId) -> Bool {
    return messages.last.map { message in
        guard let combinedReadState, combinedReadState.count > 0, !combinedReadState.isIncomingMessageIndexRead(message.index) else {
            return false
        }
        return message.effectivelyIncoming(accountPeerId) && message.media.contains(where: { media in
            if let media = media as? TelegramMediaAction, case .gramTransfer = media.action {
                return true
            }
            return false
        })
    } ?? false
}

final class ChatListGramTransferSubmoduleCompatibilityTests: XCTestCase {
    private static var retained: [NSImage] = []

    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1000))
    private let contactPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(2000))
    private let notificationsPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
        for name in ["Icon_ChatList_GramBadgeBackground", "Icon_ChatList_GramBadgeForeground"] where NSImage(named: name) == nil {
            let image = TestImages.named(name)
            _ = image.setName(name)
            Self.retained.append(image)
        }
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func collapsed(_ text: String) -> String {
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func submoduleStrings() throws -> [String: String] {
        let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private var dateTimeFormat: SubmoduleDateTimeFormat {
        return SubmoduleDateTimeFormat(groupingSeparator: Locale.current.groupingSeparator ?? ",", decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }

    private func user(_ id: PeerId) -> TelegramUser {
        return TelegramUser(id: id, accessHash: nil, firstName: "User", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func message(in peerId: PeerId, id: Int32 = 1, incoming: Bool, media: [Media], text: String = "") -> Message {
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[peerId] = user(peerId)
        return Message(stableId: UInt32(id), stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1_700_000_000 + id, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: incoming ? user(peerId) : user(accountPeerId), text: text, attributes: [], media: media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func transfer(_ amount: Int64) -> TelegramMediaAction {
        return TelegramMediaAction(action: .gramTransfer(amount: amount, peerAddress: "", transactionId: "transaction", comment: nil, commentEncrypted: false))
    }

    private let amounts: [Int64] = [1_000_000_000, 5_000_000_000, 1_500_000_000, 2_000_500_000, 1, 123_456_789, 999_999_999, 10_000_000_000_000, 1_234_567_891_000_000]

    func testPreviewTextMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        for peerId in [contactPeerId, notificationsPeerId] {
            for amount in amounts {
                let item = message(in: peerId, incoming: true, media: [transfer(amount)])
                for includeDiamond in [false, true] {
                    XCTAssertEqual(
                        incomingGramTransferPreviewText(item, accountPeerId: accountPeerId, includeDiamond: includeDiamond),
                        submoduleIncomingGramTransferPreview(message: item, accountPeerId: accountPeerId, strings: strings, dateTimeFormat: dateTimeFormat, includeDiamond: includeDiamond),
                        "\(peerId) \(amount) \(includeDiamond)"
                    )
                }
            }
        }
    }

    func testPreviewTextReadsLikeTheSubmoduleStrings() throws {
        let strings = try submoduleStrings()
        XCTAssertEqual(strings["Notification.GramTransfer.Compact"], "sent you %@")
        XCTAssertEqual(strings["Notification.GramTransferUnknown"], "Someone sent you %@")
        XCTAssertEqual(incomingGramTransferPreviewText(message(in: contactPeerId, incoming: true, media: [transfer(5_000_000_000)]), accountPeerId: accountPeerId, includeDiamond: false), "sent you 5 Grams")
        XCTAssertEqual(incomingGramTransferPreviewText(message(in: contactPeerId, incoming: true, media: [transfer(1_000_000_000)]), accountPeerId: accountPeerId, includeDiamond: true), "sent you 💎1 Gram")
        XCTAssertEqual(incomingGramTransferPreviewText(message(in: notificationsPeerId, incoming: true, media: [transfer(5_000_000_000)]), accountPeerId: accountPeerId, includeDiamond: true), "Someone sent you 💎5 Grams")
    }

    func testOnlyReceivedTransfersGetTheShortPreview() throws {
        let strings = try submoduleStrings()
        let cases: [Message] = [
            message(in: contactPeerId, incoming: false, media: [transfer(5_000_000_000)]),
            message(in: accountPeerId, incoming: false, media: [transfer(5_000_000_000)]),
            message(in: contactPeerId, incoming: true, media: [], text: "hello"),
            message(in: contactPeerId, incoming: true, media: [TelegramMediaAction(action: .historyCleared)])
        ]
        for item in cases {
            XCTAssertNil(incomingGramTransferPreviewText(item, accountPeerId: accountPeerId, includeDiamond: false))
            XCTAssertNil(submoduleIncomingGramTransferPreview(message: item, accountPeerId: accountPeerId, strings: strings, dateTimeFormat: dateTimeFormat))
        }
    }

    func testListPreviewHasNoDiamondAndNotificationsDo() throws {
        let list = collapsed(try source("submodules/telegram-ios/submodules/ChatListUI/Sources/Node/ChatListItemStrings.swift"))
        XCTAssertTrue(list.contains(collapsed("""
            case .gramTransfer where message.effectivelyIncoming(accountPeerId):
                if let preview = incomingGramTransferPreview(message: message, accountPeerId: accountPeerId, strings: strings, dateTimeFormat: dateTimeFormat) {
                    hideAuthor = true
            """)))
        let notification = collapsed(try source("submodules/telegram-ios/submodules/TelegramUI/Components/Chat/ChatMessageNotificationItem/Sources/ChatMessageNotificationItem.swift"))
        XCTAssertTrue(notification.contains(collapsed("incomingGramTransferPreview(message: EngineMessage(message), accountPeerId: item.context.account.peerId, strings: item.strings, dateTimeFormat: item.dateTimeFormat, includeDiamond: true)")))

        let textUtils = collapsed(try source("packages/MessageTextUtils/Sources/MessageTextUtils/TextUtils.swift"))
        XCTAssertTrue(textUtils.contains(collapsed("let gramTransferText = isReplied || folder ? nil : incomingGramTransferPreviewText(message, accountPeerId: account.peerId, includeDiamond: notifications)")))
        XCTAssertTrue(textUtils.contains(collapsed("_ = attributedText.append(string: gramTransferText ?? service.0, color: theme.chatList.grayTextColor, font: .normal(.text))")))
        let row = collapsed(try source("packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift"))
        XCTAssertTrue(row.contains(collapsed("messageText = chatListText(account: context.account, for: message, messagesCount: messages.count, renderedPeer: renderedPeer, draft: draft, folder: false, applyUserName: false, isPremium: context.isPremium)")))
        let notifications = collapsed(try source("Telegram-Mac/account/SharedNotificationManager.swift"))
        XCTAssertTrue(notifications.contains(collapsed("text = chatListText(account: account, for: message, applyUserName: true, notifications: true).string")))
    }

    func testSubmodulePreviewHelpersStillMatchTheCopies() throws {
        let service = collapsed(try source("submodules/telegram-ios/submodules/TelegramStringFormatting/Sources/ServiceMessageStrings.swift"))
        for line in [
            "guard message.effectivelyIncoming(accountPeerId) else { return nil }",
            "guard let media = media as? TelegramMediaAction, case let .gramTransfer(amount, _, _, _, _) = media.action else { continue }",
            "let amountText = formatTonAmountText(amount, dateTimeFormat: dateTimeFormat, maxDecimalPositions: 3, formatString: strings.Currency_Grams)",
            "let prefix = includeDiamond ? \"💎\" : \"\"",
            "if message.id.peerId.isTelegramNotifications { formatted = strings.Notification_GramTransferUnknown(prefix + amountText) } else { formatted = strings.Notification_GramTransfer_Compact(prefix + amountText) }"
        ] {
            XCTAssertTrue(service.contains(collapsed(line)), line)
        }
        let ton = collapsed(try source("submodules/telegram-ios/submodules/TelegramStringFormatting/Sources/TonFormat.swift"))
        for line in [
            "if integerPart == 0 && magnitude != 0 && fractionalPartString.allSatisfy({ $0 == \"0\" }) { fractionalPartString = fullFractionalPart }",
            "let pluralizationValue: Int32 = (integerPart == 1 && fractionalPartString.isEmpty) ? 1 : 100",
            "return formatString(pluralizationValue).replacingOccurrences(of: \"\\(pluralizationValue)\", with: balanceText)"
        ] {
            XCTAssertTrue(ton.contains(collapsed(line)), line)
        }
    }

    func testBadgeRuleMatchesSubmodule() {
        let cases: [([Message], Bool)] = [
            ([message(in: contactPeerId, incoming: true, media: [transfer(5_000_000_000)])], true),
            ([message(in: contactPeerId, incoming: false, media: [transfer(5_000_000_000)])], false),
            ([message(in: contactPeerId, id: 1, incoming: true, media: [transfer(5_000_000_000)]), message(in: contactPeerId, id: 2, incoming: true, media: [], text: "hello")], false),
            ([message(in: contactPeerId, id: 1, incoming: true, media: [], text: "hello"), message(in: contactPeerId, id: 2, incoming: true, media: [transfer(5_000_000_000)])], true),
            ([message(in: accountPeerId, incoming: false, media: [transfer(5_000_000_000)])], false),
            ([message(in: notificationsPeerId, incoming: true, media: [transfer(1)])], true),
            ([message(in: contactPeerId, incoming: true, media: [], text: "hello")], false),
            ([message(in: contactPeerId, incoming: true, media: [TelegramMediaAction(action: .historyCleared)])], false),
            ([], false)
        ]
        let unread = EnginePeerReadCounters(incomingReadId: 0, outgoingReadId: 0, count: 1, markedUnread: false)
        for (index, (messages, expected)) in cases.enumerated() {
            XCTAssertEqual(submoduleHasUnreadIncomingGramTransfer(messages, combinedReadState: unread, accountPeerId: accountPeerId), expected, "case \(index)")
            XCTAssertEqual(chatListHasUnreadIncomingGramTransfer(messages, readState: unread, accountPeerId: accountPeerId), expected, "case \(index)")
        }
    }

    func testBadgeShowsOnlyWhileTheTransferIsUnreadLikeSubmodule() {
        let messages = [message(in: contactPeerId, id: 5, incoming: true, media: [transfer(5_000_000_000)])]
        let readStates: [(EnginePeerReadCounters?, Bool)] = [
            (nil, false),
            (EnginePeerReadCounters(), false),
            (EnginePeerReadCounters(incomingReadId: 4, outgoingReadId: 0, count: 1, markedUnread: false), true),
            (EnginePeerReadCounters(incomingReadId: 4, outgoingReadId: 0, count: 3, markedUnread: false), true),
            (EnginePeerReadCounters(incomingReadId: 5, outgoingReadId: 0, count: 1, markedUnread: false), false),
            (EnginePeerReadCounters(incomingReadId: 9, outgoingReadId: 0, count: 2, markedUnread: false), false),
            (EnginePeerReadCounters(incomingReadId: 4, outgoingReadId: 0, count: 0, markedUnread: false), false),
            (EnginePeerReadCounters(incomingReadId: 5, outgoingReadId: 0, count: 0, markedUnread: true), false),
            (EnginePeerReadCounters(incomingReadId: 4, outgoingReadId: 0, count: 0, markedUnread: true), false)
        ]
        for (index, (readState, expected)) in readStates.enumerated() {
            XCTAssertEqual(submoduleHasUnreadIncomingGramTransfer(messages, combinedReadState: readState, accountPeerId: accountPeerId), expected, "read state \(index)")
            XCTAssertEqual(chatListHasUnreadIncomingGramTransfer(messages, readState: readState, accountPeerId: accountPeerId), expected, "read state \(index)")
        }
    }

    func testGramBadgeHidesTheUnreadCounterOfOneLikeSubmodule() {
        func submoduleShowsUnreadCounter(count: Int32, hasUnreadIncomingGramTransfer: Bool) -> Bool {
            var showsCounter = count > 0
            if hasUnreadIncomingGramTransfer, count == 1 {
                showsCounter = false
            }
            return showsCounter
        }
        let messages = [message(in: contactPeerId, id: 5, incoming: true, media: [transfer(5_000_000_000)])]
        for count in [0, 1, 2, 3, 12] as [Int32] {
            for incomingReadId in [4, 5] as [Int32] {
                let readState = EnginePeerReadCounters(incomingReadId: incomingReadId, outgoingReadId: 0, count: count, markedUnread: false)
                let submoduleHasGram = submoduleHasUnreadIncomingGramTransfer(messages, combinedReadState: readState, accountPeerId: accountPeerId)
                let actualHasGram = chatListHasUnreadIncomingGramTransfer(messages, readState: readState, accountPeerId: accountPeerId)
                XCTAssertEqual(actualHasGram, submoduleHasGram)
                let actualShowsCounter = !chatListGramBadgeHidesUnreadCounter(hasGramBadge: actualHasGram, unreadCount: readState.count) && readState.count > 0
                XCTAssertEqual(actualShowsCounter, submoduleShowsUnreadCounter(count: count, hasUnreadIncomingGramTransfer: submoduleHasGram), "count \(count) read \(incomingReadId)")
            }
        }
        XCTAssertTrue(chatListGramBadgeHidesUnreadCounter(hasGramBadge: true, unreadCount: 1))
        XCTAssertFalse(chatListGramBadgeHidesUnreadCounter(hasGramBadge: true, unreadCount: 2))
        XCTAssertFalse(chatListGramBadgeHidesUnreadCounter(hasGramBadge: false, unreadCount: 1))
        XCTAssertFalse(chatListGramBadgeHidesUnreadCounter(hasGramBadge: true, unreadCount: nil))
    }

    func testSubmoduleBadgeRuleIsUnchanged() throws {
        let item = collapsed(try source("submodules/telegram-ios/submodules/ChatListUI/Sources/Node/ChatListItem.swift"))
        XCTAssertTrue(item.contains(collapsed("""
            let hasUnreadIncomingGramTransfer = messages.last.map { message in
                guard let combinedReadState, combinedReadState.count > 0, !combinedReadState.isIncomingMessageIndexRead(message.index) else {
                    return false
                }
                return message.effectivelyIncoming(account.peerId) && message.media.contains(where: { media in
                    if let media = media as? TelegramMediaAction, case .gramTransfer = media.action {
                        return true
                    }
                    return false
                })
            } ?? false
            if hasUnreadIncomingGramTransfer {
                currentMentionBadgeImage = PresentationResourcesChatList.badgeBackgroundGram(item.presentationData.theme, diameter: badgeDiameter, inactive: isRemovedFromTotalUnreadCount)
                mentionBadgeContent = .mention
                if unreadCount.count == 1 {
                    badgeContent = .none
                    currentBadgeBackgroundImage = nil
                    currentAvatarBadgeBackgroundImage = nil
                }
            } else if hasUnseenMentions {
            """)))
        XCTAssertTrue(item.contains(collapsed("""
                mentionBadgeContent = .mention
            } else if item.isPinned, promoInfo == nil, currentBadgeBackgroundImage == nil {
                currentPinnedIconImage = PresentationResourcesChatList.badgeBackgroundPinned(item.presentationData.theme, diameter: badgeDiameter)
            }
            """)))
        let resources = collapsed(try source("submodules/telegram-ios/submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChatList.swift"))
        XCTAssertTrue(resources.contains(collapsed("""
            let color = inactive ? theme.chatList.unreadBadgeInactiveBackgroundColor : theme.chatList.unreadBadgeActiveBackgroundColor
            return generateImage(CGSize(width: diameter, height: diameter), contextGenerator: { size, context in
                context.clear(CGRect(origin: .zero, size: size))

                if let background = generateTintedImage(image: UIImage(bundleImageName: "Chat List/GramIconBackground"), color: color), let cgImage = background.cgImage {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                }

                if let foreground = UIImage(bundleImageName: "Chat List/GramIconForeground"), let cgImage = foreground.cgImage {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                }
            })
            """)))
        let row = collapsed(try source("packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift"))
        XCTAssertTrue(row.contains(collapsed("""
            guard let readState, readState.count > 0, !readState.isIncomingMessageIndexRead(MessageIndex(message)) else {
                return false
            }
            """)))
    }

    func testGramBadgeTakesTheBadgeSlotAlone() throws {
        let row = collapsed(try source("packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift"))
        for line in [
            "self.hasGramBadge = chatListHasUnreadIncomingGramTransfer(messages, readState: readState, accountPeerId: context.peerId)",
            "if hasUnreadMentions && !hasGramBadge { self.mentionsCount = 1 } else { self.mentionsCount = nil }",
            "if hasUnreadReactions && !hasGramBadge { self.reactionsCount = 1 } else { self.reactionsCount = nil }",
            "if hasUnreadVotes && !hasGramBadge { self.pollVotesCount = 1 } else { self.pollVotesCount = nil }",
            "public var showsMentionSlot: Bool { return mentionsCount != nil || hasGramBadge }",
            "if showBadge, !chatListGramBadgeHidesUnreadCounter(hasGramBadge: hasGramBadge, unreadCount: readState?.count) {",
            "func chatListGramBadgeHidesUnreadCounter(hasGramBadge: Bool, unreadCount: Int32?) -> Bool { return hasGramBadge && unreadCount == 1 }",
            "return !isSecret && !isUnreadMarked && badgeNode == nil && !showsMentionSlot && !self.mode.savedMessages",
            "let isUnread = badgeNode != nil || showsMentionSlot || isUnreadMarked"
        ] {
            XCTAssertTrue(row.contains(collapsed(line)), line)
        }
        XCTAssertEqual(row.components(separatedBy: "if showsMentionSlot { w += 24 }").count - 1, 3)
        let view = collapsed(try source("packages/ChatListUI/Sources/ChatListUI/ChatListRowView.swift"))
        for line in [
            "if item.showsMentionSlot { let highlighted = self.highlighed let icon: CGImage if item.hasGramBadge { icon = chatListGramBadgeIcon(highlighted: highlighted, muted: item.badgeMuted) } else if item.associatedGroupId == .root {",
            "if item.ctxBadgeNode == nil && !item.showsMentionSlot && (item.isPinned || item.isLastPinned) {"
        ] {
            XCTAssertTrue(view.contains(collapsed(line)), line)
        }
        XCTAssertEqual(view.components(separatedBy: "(item.showsMentionSlot ? 20 + item.margin : 0)").count - 1, 2)
    }

    func testBotOpenButtonGivesWayToTheGramBadgeLikeSubmodule() throws {
        let item = collapsed(try source("submodules/telegram-ios/submodules/ChatListUI/Sources/Node/ChatListItem.swift"))
        XCTAssertTrue(item.contains(collapsed("if !item.editing, !item.interaction.isSideListMode, case .none = badgeContent, case .none = mentionBadgeContent, case let .chat(itemPeer) = contentPeer, case let .user(user) = itemPeer.chatMainPeer, let botInfo = user.botInfo, botInfo.flags.contains(.hasWebApp) {")))

        let row = try source("packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift")
        XCTAssertTrue(collapsed(row).contains(collapsed("""
            self.hasGramBadge = chatListHasUnreadIncomingGramTransfer(messages, readState: readState, accountPeerId: context.peerId)

            if let peer, let botInfo = peer.botInfo, botInfo.flags.contains(.hasWebApp), readState == nil || readState?.count == 0, !hasGramBadge, splitState != .minimisize {
            """)))
        XCTAssertEqual(row.components(separatedBy: "self.hasGramBadge = chatListHasUnreadIncomingGramTransfer(").count - 1, 1)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private func submoduleBadgeLayer(_ name: String, pixelSize: Int) throws -> CGImage {
        let file = name == "GramIconBackground" ? "chatgrambg.pdf" : "chatgramfg.pdf"
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Images.xcassets/Chat List/\(name).imageset/\(file)")
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(pixelSize) / box.width, y: CGFloat(pixelSize) / box.height)
        context.drawPDFPage(page)
        return try XCTUnwrap(context.makeImage())
    }

    private func submoduleBadge(color: NSColor, pixelSize: Int) throws -> CGImage {
        let background = try submoduleBadgeLayer("GramIconBackground", pixelSize: pixelSize)
        let foreground = try submoduleBadgeLayer("GramIconForeground", pixelSize: pixelSize)
        let rect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.saveGState()
        context.clip(to: rect, mask: background)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.restoreGState()
        context.draw(foreground, in: rect)
        return try XCTUnwrap(context.makeImage())
    }

    private func maxDifference(_ lhs: [UInt8], _ rhs: [UInt8], channels: [Int] = [0, 1, 2, 3]) -> Int {
        var result = 0
        for index in stride(from: 0, to: min(lhs.count, rhs.count), by: 4) {
            for channel in channels {
                result = max(result, abs(Int(lhs[index + channel]) - Int(rhs[index + channel])))
            }
        }
        return result
    }

    func testBadgeLayersAreTheSubmoduleArtwork() throws {
        for (name, submoduleName) in [("Icon_ChatList_GramBadgeBackground", "GramIconBackground"), ("Icon_ChatList_GramBadgeForeground", "GramIconForeground")] {
            let image = try XCTUnwrap(NSImage(named: name))
            XCTAssertEqual(image.size, NSSize(width: 20, height: 20), name)
            for scale in [1, 2] {
                let rep = try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first(where: { $0.pixelsWide == 20 * scale }), "\(name) @\(scale)x")
                let actual = pixels(try XCTUnwrap(rep.cgImage))
                let expected = pixels(try submoduleBadgeLayer(submoduleName, pixelSize: 20 * scale))
                XCTAssertLessThanOrEqual(maxDifference(actual, expected), 2, "\(name) @\(scale)x")
            }
        }
        let star = pixels(try submoduleBadgeLayer("GramIconForeground", pixelSize: 40))
        for index in stride(from: 0, to: star.count, by: 4) where star[index + 3] == 255 {
            XCTAssertEqual([star[index], star[index + 1], star[index + 2]], [255, 255, 255])
        }
    }

    func testBadgeIconHasTheSubmoduleShapeAtTheMentionBadgeSize() throws {
        let icon = chatListGramBadgeIcon(highlighted: false, muted: false)
        XCTAssertEqual(icon.width, theme.icons.chatListMention.width)
        XCTAssertEqual(icon.height, theme.icons.chatListMention.height)
        XCTAssertEqual(icon.width, 40)

        let expected = pixels(try submoduleBadge(color: theme.chatList.badgeBackgroundColor, pixelSize: icon.width))
        let actual = pixels(icon)
        XCTAssertLessThanOrEqual(maxDifference(actual, expected), 3)
        let opaque = stride(from: 3, to: actual.count, by: 4).filter { actual[$0] > 0 }.count
        XCTAssertGreaterThan(opaque, 600)
    }

    private func rgb(_ color: NSColor) -> (red: Int, green: Int, blue: Int) {
        let color = color.usingColorSpace(.sRGB)!
        return (Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    func testBadgeStarStaysWhiteInDarkThemesLikeSubmodule() throws {
        let previous = theme
        defer {
            telegramUpdateTheme(previous, window: nil, animated: false)
        }
        telegramUpdateTheme(generateTheme(palette: darkPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), window: nil, animated: false)
        let badgeText = rgb(theme.chatList.badgeTextColor)
        XCTAssertFalse(badgeText.red == 255 && badgeText.green == 255 && badgeText.blue == 255)
        for muted in [false, true] {
            let icon = chatListGramBadgeIcon(highlighted: false, muted: muted)
            let expected = pixels(try submoduleBadge(color: muted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor, pixelSize: icon.width))
            XCTAssertLessThanOrEqual(maxDifference(pixels(icon), expected), 3, "muted \(muted)")
        }
    }

    func testBadgeColorsFollowTheUnreadBadgeLikeSubmodule() throws {
        let cases: [(highlighted: Bool, muted: Bool, color: NSColor)] = [
            (false, false, theme.chatList.badgeBackgroundColor),
            (false, true, theme.chatList.badgeMutedBackgroundColor)
        ]
        for item in cases {
            let icon = chatListGramBadgeIcon(highlighted: item.highlighted, muted: item.muted)
            let expected = pixels(try submoduleBadge(color: item.color, pixelSize: icon.width))
            XCTAssertLessThanOrEqual(maxDifference(pixels(icon), expected), 3, "\(item)")
        }

        let selected = chatListGramBadgeIcon(highlighted: true, muted: false)
        let selectedPixels = pixels(selected)
        let star = pixels(try submoduleBadgeLayer("GramIconForeground", pixelSize: selected.width))
        let diamondColor = rgb(theme.chatList.badgeSelectedBackgroundColor)
        let starColor = rgb(theme.chatList.badgeSelectedTextColor)
        var checkedStar = 0
        var checkedDiamond = 0
        for index in stride(from: 0, to: selectedPixels.count, by: 4) where selectedPixels[index + 3] == 255 {
            let pixel = (red: Int(selectedPixels[index]), green: Int(selectedPixels[index + 1]), blue: Int(selectedPixels[index + 2]))
            let expected = star[index + 3] == 255 ? starColor : (star[index + 3] == 0 ? diamondColor : nil)
            guard let expected else { continue }
            XCTAssertLessThanOrEqual(abs(pixel.red - expected.red), 2)
            XCTAssertLessThanOrEqual(abs(pixel.green - expected.green), 2)
            XCTAssertLessThanOrEqual(abs(pixel.blue - expected.blue), 2)
            if star[index + 3] == 255 { checkedStar += 1 } else { checkedDiamond += 1 }
        }
        XCTAssertGreaterThan(checkedStar, 20)
        XCTAssertGreaterThan(checkedDiamond, 400)

        let row = collapsed(try source("packages/ChatListUI/Sources/ChatListUI/ChatListRowItem.swift"))
        XCTAssertTrue(row.contains(collapsed("badgeNode = BadgeNode(.initialize(string: \"\\(unreadCount)\", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)")))
        let resources = collapsed(try source("submodules/telegram-ios/submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChatList.swift"))
        XCTAssertTrue(resources.contains(collapsed("""
            } else {
                context.setFillColor(theme.chatList.unreadBadgeActiveBackgroundColor.cgColor)
            }
            } else {
                if provisional {
                    context.setFillColor(theme.chatList.unreadBadgeInactiveBackgroundColor.withMultipliedAlpha(0.2).cgColor)
                } else {
                    context.setFillColor(theme.chatList.unreadBadgeInactiveBackgroundColor.cgColor)
                }
            }
            """)))
    }
}
