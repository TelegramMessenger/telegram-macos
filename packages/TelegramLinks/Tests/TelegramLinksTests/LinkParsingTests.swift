import XCTest
import Postbox
import TelegramCore
@testable import TelegramLinks

final class LinkParsingTests: XCTestCase {
    private var enabled: InAppLinkParsingOptions {
        InAppLinkParsingOptions(hasContext: true, hasOpenInfo: true, hasHashtag: true, hasCommand: true, hasApplyProxy: true)
    }

    private func parse(_ value: String, options: InAppLinkParsingOptions? = nil) -> ParsedInAppLink {
        parseInAppLink(value as NSString, options: options ?? enabled)
    }

    private func assertPeer(_ value: String, username: String, post: Int32? = nil, action: ParsedChatLinkAction? = nil, options: InAppLinkParsingOptions? = nil, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .followResolvedName(_, actualName, actualPost, _, actualAction) = parse(value, options: options) else {
            return XCTFail("Expected a peer link: \(value)", file: file, line: line)
        }
        XCTAssertEqual(actualName, username, file: file, line: line)
        XCTAssertEqual(actualPost, post, file: file, line: line)
        XCTAssertEqual(actualAction, action, file: file, line: line)
    }

    func testTelegramDomainsAndSubdomains() {
        for domain in ["t.me", "telegram.me", "telegram.dog"] {
            assertPeer("https://\(domain)/alice/42", username: "alice", post: 42)
        }
        assertPeer("https://alice.t.me/42", username: "alice", post: 42)
        assertPeer("@alice", username: "alice")
        assertPeer("TG://resolve?domain=alice&post=42", username: "alice", post: 42)
    }

    func testFreeMessageLinks() {
        let cases = [
            ("t.me/user?free=AAAA", "user", "AAAA"),
            ("tg://resolve?username=user&free=AAAA", "user", "AAAA"),
            ("t.me/+1112223333?free=AAAA", "1112223333", "AAAA"),
            ("tg://resolve?phone=1112223333&free=AAAA", "1112223333", "AAAA"),
            ("https://t.me/user?free=AbC_123-xy", "user", "AbC_123-xy"),
            ("https://t.me/+1112223333?free=AbC_123-xy", "1112223333", "AbC_123-xy"),
            ("tg://resolve?domain=user&free=AbC_123-xy", "user", "AbC_123-xy"),
            ("TG://resolve?username=user&free=AbC%2B123%3D", "user", "AbC+123=")
        ]
        for (value, expectedTarget, expectedToken) in cases {
            guard case let .noPaidMessagesToken(link, target, token) = parse(value) else {
                XCTFail("Expected a free message link: \(value)")
                continue
            }
            XCTAssertEqual(link, normalizeURLScheme(value as NSString) as String)
            XCTAssertEqual(target, expectedTarget, value)
            XCTAssertEqual(token, expectedToken, value)
        }
    }

    func testContactLinksPreserveFreeMessageToken() {
        for value in ["https://t.me/contact/XXXX:YYYZZZ?free=AABBCC", "tg://contact?token=XXXX%3AYYYZZZ&free=AABBCC"] {
            guard case let .contactToken(_, token, freeToken) = parse(value) else {
                XCTFail("Expected contact link: \(value)")
                continue
            }
            XCTAssertEqual(token, "XXXX:YYYZZZ")
            XCTAssertEqual(freeToken, "AABBCC")
        }
        for value in ["t.me/contact/XXXX:YYYZZZ", "tg://contact?token=XXXX:YYYZZZ&free="] {
            guard case let .contactToken(_, token, freeToken) = parse(value) else {
                XCTFail("Expected ordinary contact link: \(value)")
                continue
            }
            XCTAssertEqual(token, "XXXX:YYYZZZ")
            XCTAssertNil(freeToken)
        }
    }

    func testContactLinksRequireNavigation() {
        for options in [InAppLinkParsingOptions(), InAppLinkParsingOptions(hasContext: true), InAppLinkParsingOptions(hasOpenInfo: true)] {
            guard case .external = parse("https://t.me/contact/XXXX:YYYZZZ?free=AABBCC", options: options) else {
                return XCTFail("Web contact links require navigation")
            }
            guard case .nothing = parse("tg://contact?token=XXXX:YYYZZZ&free=AABBCC", options: options) else {
                return XCTFail("Contact scheme links require navigation")
            }
        }
    }

    func testFreeMessageLinksRequireTokenAndNavigation() {
        for query in ["free", "free="] {
            assertPeer("https://t.me/user?\(query)", username: "user")
            assertPeer("https://t.me/+1112223333?\(query)", username: "1112223333")
            assertPeer("tg://resolve?domain=user&\(query)", username: "user")
            assertPeer("tg://resolve?phone=1112223333&\(query)", username: "1112223333")
        }
        for options in [InAppLinkParsingOptions(), InAppLinkParsingOptions(hasContext: true), InAppLinkParsingOptions(hasOpenInfo: true)] {
            for value in ["https://t.me/user?free=AAAA", "https://t.me/+1112223333?free=AAAA"] {
                guard case .external = parse(value, options: options) else {
                    XCTFail("A free message web link requires context and openInfo: \(value)")
                    continue
                }
            }
            for value in ["tg://resolve?username=user&free=AAAA", "tg://resolve?domain=user&free=AAAA", "tg://resolve?phone=1112223333&free=AAAA"] {
                guard case .nothing = parse(value, options: options) else {
                    XCTFail("A free message scheme link requires context and openInfo: \(value)")
                    continue
                }
            }
        }
        guard case .nothing = parse("tg://resolve?free=AAAA") else {
            return XCTFail("A free message link requires a recipient")
        }
    }

    func testContextAndCallbackAvailabilityPreservesFallback() {
        for options in [InAppLinkParsingOptions(), InAppLinkParsingOptions(hasContext: true), InAppLinkParsingOptions(hasOpenInfo: true)] {
            guard case .external = parse("https://t.me/alice", options: options) else {
                return XCTFail("A peer web link requires context and openInfo")
            }
            guard case .nothing = parse("tg://resolve?domain=alice", options: options) else {
                return XCTFail("A recognized scheme without its requirements returns nothing")
            }
        }
        guard case let .external(value, confirm) = parse("https://example.com", options: InAppLinkParsingOptions(confirm: true)) else {
            return XCTFail("Expected external link")
        }
        XCTAssertEqual(value, "https://example.com")
        XCTAssertTrue(confirm)
    }

    func testCommandsAndHashtagsRequireOnlyTheirCallbackCapability() {
        guard case let .botCommand(command) = parse("/help", options: InAppLinkParsingOptions(hasCommand: true)) else {
            return XCTFail("Expected command")
        }
        XCTAssertEqual(command, "/help")
        for value in ["#topic", "$topic"] {
            guard case let .hashtag(tag) = parse(value, options: InAppLinkParsingOptions(hasHashtag: true)) else {
                return XCTFail("Expected hashtag")
            }
            XCTAssertEqual(tag, value)
        }
        for value in ["/help", "#topic"] {
            guard case .external = parse(value, options: InAppLinkParsingOptions()) else {
                return XCTFail("Missing callbacks must preserve external fallback")
            }
        }
    }

    func testChatActionPayloads() {
        assertPeer("https://t.me/alice?start=hello%20world", username: "alice", action: .start(parameter: "hello world", behavior: .none))
        assertPeer("tg://resolve?domain=alice&text=hello%20world", username: "alice", action: .inputText(text: "hello world", behavior: .automatic))
        assertPeer("tg://resolve?domain=alice&voicechat", username: "alice", action: .joinVoiceChat(nil))
        assertPeer("tg://resolve?domain=alice&voicechat=abc", username: "alice", action: .joinVoiceChat("abc"))
        assertPeer("tg://resolve?domain=alice&videochat", username: "alice", action: .joinVoiceChat(nil))
        assertPeer("tg://resolve?domain=alice&videochat=abc", username: "alice", action: .joinVoiceChat("abc"))
        assertPeer("tg://resolve?domain=alice&livestream=abc", username: "alice", action: .joinVoiceChat("abc"))
        assertPeer("https://t.me/alice?videochat", username: "alice", action: .joinVoiceChat(nil))
        assertPeer("https://t.me/alice?videochat=abc", username: "alice", action: .joinVoiceChat("abc"))
        assertPeer("https://t.me/alice?voicechat", username: "alice", action: .joinVoiceChat(nil))
        assertPeer("tg://resolve?domain=alice&startapp", username: "alice", action: .makeWebview(appname: "", command: nil))
        assertPeer("tg://resolve?domain=alice&attach=bot&choose=users+groups", username: "alice", action: .attachBot("bot", nil, ["bot"]))
        assertPeer("tg://resolve?domain=alice&direct", username: "alice", action: .direct)
        assertPeer("https://t.me/alice/app?startapp=payload", username: "alice", action: .makeWebview(appname: "app", command: "payload"))
        assertPeer("https://t.me/alice/a/4", username: "alice", action: .album(album: 4, mode: .stories))
        assertPeer("https://t.me/alice/c/5", username: "alice", action: .album(album: 5, mode: .gifts))
    }

    func testSourceMessageTimecodesAndPollOptions() {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1))
        let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 7)
        var options = enabled
        options.messageId = messageId
        assertPeer("https://t.me/alice/42", username: "alice", post: 42, action: .source(messageId, nil), options: options)
        assertPeer("https://t.me/alice/42?t=1h2m3s", username: "alice", post: 42, action: .openMedia(3723))
        assertPeer("https://t.me/c/123/42?t=90", username: "_private_123", post: 42, action: .openMedia(90))
        assertPeer("https://t.me/alice/42?t=90&option=AQ", username: "alice", post: 42, action: .pollOption(Data([1])))
    }

    func testTopicsCommentsAndStories() {
        guard case let .comments(_, username, thread, comment) = parse("https://t.me/alice/42?comment=7") else {
            return XCTFail("Expected comments")
        }
        XCTAssertEqual(username, "alice")
        XCTAssertEqual(thread, 42)
        XCTAssertEqual(comment, 7)
        guard case let .topic(_, name, topic, post) = parse("https://t.me/c/123/4/42") else {
            return XCTFail("Expected private topic")
        }
        XCTAssertEqual(name, "_private_123")
        XCTAssertEqual(topic, 4)
        XCTAssertEqual(post, 42)
        guard case let .story(_, storyName, id, _) = parse("https://t.me/alice/s/9") else {
            return XCTFail("Expected story")
        }
        XCTAssertEqual(storyName, "alice")
        XCTAssertEqual(id, 9)
    }

    func testInvitesAndBotInvitation() {
        for url in ["https://t.me/+abc", "https://t.me/joinchat/abc", "tg://join?invite=abc"] {
            guard case let .joinchat(_, hash) = parse(url) else { return XCTFail("Expected invite: \(url)") }
            XCTAssertEqual(hash, "abc")
        }
        guard case let .inviteBotToGroup(_, name, action, rights, isChannel) = parse("tg://resolve?domain=bot&startchannel&admin=post_messages") else {
            return XCTFail("Expected bot invite")
        }
        XCTAssertEqual(name, "bot")
        XCTAssertNil(action)
        XCTAssertEqual(rights, "post_messages")
        XCTAssertTrue(isChannel)
    }

    func testSettingsDestinationsAndUnknownSections() {
        let cases: [(String, InAppSettingsSection)] = [
            ("tg://settings", .general),
            ("tg://settings/privacy/auto-delete/delete-all", .privacy(.auto_delete(.delete_all))),
            ("tg://settings/appearance/stickers-and-emoji/emoji", .appearance(.stickers_and_emoji(.emoji))),
            ("tg://settings/data/proxy/add", .data(.proxy(.add))),
            ("tg://settings/notifications/groups/sound", .notifications(.groups(.sound))),
            ("tg://settings/notifications/private-chats/add-exception", .notifications(.private_chats(.add_exception))),
            ("tg://settings/notifications/channels/preview", .notifications(.channels(.preview))),
            ("tg://settings/notifications/stories/show-sender", .notifications(.stories(.show_sender))),
            ("tg://settings/notifications/reactions", .notifications(.reactions(nil))),
            ("tg://settings/notifications/reactions/messages", .notifications(.reactions(.messages))),
            ("tg://settings/notifications/reset", .notifications(.reset)),
            ("tg://settings/edit/username", .edit_profile(.username)),
            ("tg://settings/privacy/unknown", .privacy(nil))
        ]
        for (url, expected) in cases {
            guard case let .settings(_, section) = parse(url) else { return XCTFail("Expected settings: \(url)") }
            XCTAssertEqual(section, expected)
        }
        guard case .nothing = parse("tg://settings/unknown") else { return XCTFail("Expected nothing") }
    }

    func testStickerPackKindsAndPeerIdentifiers() {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(9))
        var options = enabled
        options.peerId = peerId
        guard case let .stickerPack(_, source, actualPeer) = parse("https://t.me/addstickers/cats", options: options) else {
            return XCTFail("Expected stickers")
        }
        XCTAssertEqual(source, .stickers("cats"))
        XCTAssertEqual(actualPeer, peerId)
        guard case let .stickerPack(_, emoji, schemePeer) = parse("tg://addemoji?set=cats", options: options) else {
            return XCTFail("Expected emoji")
        }
        XCTAssertEqual(emoji, .emoji("cats"))
        XCTAssertNil(schemePeer)
    }

    func testProxyLinksAndMissingRequirements() {
        for url in ["tg://socks?server=localhost&port=1080&user=alice&pass=secret", "https://t.me/socks?server=localhost&port=1080&user=alice&pass=secret"] {
            guard case let .socks(_, settings) = parse(url) else { return XCTFail("Expected socks proxy") }
            XCTAssertEqual(settings.host, "localhost")
            XCTAssertEqual(settings.port, 1080)
            guard case let .socks5(username, password) = settings.connection else { return XCTFail("Expected SOCKS5") }
            XCTAssertEqual(username, "alice")
            XCTAssertEqual(password, "secret")
        }
        let secret = String(repeating: "01", count: 16)
        guard case let .socks(_, settings) = parse("tg://proxy?server=localhost&port=443&secret=\(secret)") else {
            return XCTFail("Expected MTProto proxy")
        }
        guard case .mtp = settings.connection else { return XCTFail("Expected MTProto") }
        guard case .socks = parse("tg://webproxy?server=example.com&secret=\(secret)") else {
            return XCTFail("Expected web proxy")
        }
        for url in ["tg://socks?server=localhost&port=bad", "tg://proxy?server=localhost&port=443&secret=invalid"] {
            guard case .nothing = parse(url) else { return XCTFail("Malformed proxy must not be accepted") }
        }
        guard case .nothing = parse("tg://socks?server=localhost&port=1080", options: InAppLinkParsingOptions(hasContext: true)) else {
            return XCTFail("Proxy links require applyProxy")
        }
        XCTAssertNotNil(proxySettings(from: "tg://socks?server=localhost&port=1080").0)
        XCTAssertNil(proxySettings(from: "https://t.me/socks?server=localhost&port=1080").0)
    }

    func testWalletTransferDataAndMissingContext() {
        let value = "ton://transfer/address?amount=123&text=hello%20world"
        guard case let .tonTransfer(_, data) = parse(value) else { return XCTFail("Expected transfer") }
        XCTAssertEqual(data.address, "address")
        XCTAssertEqual(data.amount, 123)
        XCTAssertEqual(data.comment, "hello world")
        guard case .nothing = parse(value, options: InAppLinkParsingOptions()) else { return XCTFail("Context required") }
        XCTAssertNil(parseWalletUrl(URL(string: "ton://transfer/")!))
        XCTAssertNil(parseWalletUrl(URL(string: "https://transfer/address")!))
        XCTAssertNil(parseWalletUrl(URL(string: "ton://transfer/address?amount=bad")!)?.amount)
    }

    func testTelegramLinkQueryNormalization() {
        XCTAssertEqual(
            normalizedTelegramLinkQuery("tg://sendgrams&startapp=tonconnect-v__2"),
            "tg://sendgrams?startapp=tonconnect-v__2"
        )
        XCTAssertEqual(
            normalizedTelegramLinkQuery("telegram://sendgrams&startapp=a&b=c"),
            "telegram://sendgrams?startapp=a&b=c"
        )
        for unchanged in [
            "tg://sendgrams?startapp=a&b=c",
            "tg://resolve?domain=alice",
            "tg://sendgrams",
            "https://t.me/sendgrams&startapp=a"
        ] {
            XCTAssertEqual(normalizedTelegramLinkQuery(unchanged), unchanged, unchanged)
        }
    }

    func testSendGramsLinks() {
        let address = "UQA4a56Xk3ZyZ8Hn0fbrkDsGqfvlBkq1pX9hC2uWhvbZcyGL"
        let cases: [(String, ParsedSendGramsLink)] = [
            ("", .wallet),
            ("?to=@monk", .send(recipient: .username("monk"), amount: nil)),
            ("?to=%40monk", .send(recipient: .username("monk"), amount: nil)),
            ("?to=\(address)", .send(recipient: .address(address), amount: nil)),
            ("?to=@monk&amount=200", .send(recipient: .username("monk"), amount: 200_000_000_000)),
            ("?to=@monk&amount=200.5", .send(recipient: .username("monk"), amount: 200_500_000_000)),
            ("?to=@monk&amount=0.000000001", .send(recipient: .username("monk"), amount: 1)),
            ("?amount=200", .invalid),
            ("?to=@monk&amount=200,5", .invalid),
            ("?to=@monk&amount=200.", .invalid),
            ("?to=@monk&amount=.5", .invalid),
            ("?to=@monk&amount=0", .invalid),
            ("?to=@monk&amount=-1", .invalid),
            ("?to=@monk&amount=1.0000000001", .invalid),
            ("?to=@monk&amount=99999999999", .invalid),
            ("?to=@", .invalid),
            ("?to=@bad-name", .invalid),
            ("?to=not%20an%20address", .invalid),
            ("?to=https://example.com", .invalid),
            ("?to=short", .invalid),
        ]
        for (query, expected) in cases {
            for base in ["https://t.me/sendgrams", "tg://sendgrams"] {
                guard case let .sendGrams(_, data) = parse(base + query) else {
                    XCTFail("Expected sendgrams: \(base + query)")
                    continue
                }
                XCTAssertEqual(data, expected, base + query)
            }
        }
        guard case .sendGrams(_, .wallet) = parse("https://t.me/SendGrams/") else { return XCTFail("Expected sendgrams") }
        let tonConnectStart = "https://t.me/sendgrams?startapp=tonconnect-v__2-id__ca7fa7bada33f4040f13abd9d1bcbfa9404f23ae250df0bfbfb9a209bd421706-ret__back"
        guard case .sendGrams(_, .wallet) = parse(tonConnectStart) else {
            return XCTFail("A TON Connect start parameter must not be read as a transfer")
        }
        assertPeer("https://t.me/sendgramsbot", username: "sendgramsbot")
        guard case .nothing = parse("tg://sendgramsbot") else { return XCTFail("Only the exact action matches") }
        guard case .external = parse("https://t.me/sendgrams?to=@monk", options: InAppLinkParsingOptions()) else { return XCTFail("Context required") }
        guard case .nothing = parse("tg://sendgrams?to=@monk", options: InAppLinkParsingOptions()) else { return XCTFail("Context required") }
    }

    func testTonSitesAndURLAuthenticationPrecedence() {
        guard case let .tonsite(value) = parse("https://alice.ton/path") else { return XCTFail("Expected tonsite") }
        XCTAssertEqual(value, "tonsite://alice.ton/path")
        var options = enabled
        options.urlAuthDomains = ["t.me"]
        guard case .urlAuth = parse("https://t.me/alice", options: options) else { return XCTFail("Authentication precedes peer parsing") }
        options.hasContext = false
        guard case .external = parse("https://t.me/alice", options: options) else { return XCTFail("Authentication requires context") }
    }

    func testWallpaperSettings() {
        guard case let .wallpaper(_, .gradient(_, colors, settings)) = parse("https://t.me/bg/ff0000~00ff00?rotation=45&intensity=20&mode=blur") else {
            return XCTFail("Expected gradient")
        }
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(settings.rotation, 45)
        XCTAssertEqual(settings.intensity, 20)
        XCTAssertTrue(settings.blur)
        guard case let .wallpaper(_, .slug(slug, invalidSettings)) = parse("tg://bg?slug=wallpaper&rotation=46") else {
            return XCTFail("Expected wallpaper slug")
        }
        XCTAssertEqual(slug, "wallpaper")
        XCTAssertNil(invalidSettings.rotation)
    }

    func testSecureIDLegacyAndModernPayloads() {
        let cases = [
            ("tg://passport?bot_id=123&scope=identity&public_key=key&payload=abc", false, "identity"),
            ("tg://resolve?domain=telegrampassport&bot_id=123&scope=%7B%7D&public_key=key&nonce=abc", true, "{}")
        ]
        for (url, modern, scope) in cases {
            guard case let .requestSecureId(_, request) = parse(url) else { return XCTFail("Expected secure ID") }
            XCTAssertEqual(request.scope, scope)
            XCTAssertEqual(request.isModern, modern)
            XCTAssertEqual(request.publicKey, "key")
            XCTAssertEqual(request.nonce, Data("abc".utf8))
        }
    }

    func testSharingAndLoginWithoutNavigation() {
        guard case let .shareUrl(_, url, text) = parse("tg://msg_url?url=https%3A%2F%2Fexample.com&text=hello+world") else {
            return XCTFail("Expected share data")
        }
        XCTAssertEqual(url, "https://example.com")
        XCTAssertEqual(text, "hello world")
        guard case let .loginCode(_, code) = parse("tg://login?code=12345", options: InAppLinkParsingOptions()) else {
            return XCTFail("Login code does not require context")
        }
        XCTAssertEqual(code, "12345")
    }

    func testUnknownAndFileSchemes() {
        guard case .nothing = parse("file:///tmp/example") else { return XCTFail("File links must not execute") }
        guard case let .unsupportedScheme(_, path) = parse("tg://unknown?value=1") else { return XCTFail("Expected unsupported scheme") }
        XCTAssertEqual(path, "unknown")
        guard case .external = parse("tg://unknown", options: InAppLinkParsingOptions()) else { return XCTFail("Expected external fallback") }
        guard case .nothing = parse("tg://resolve") else { return XCTFail("Missing required arguments") }
    }

    func testFeatureRoutePayloads() {
        let cases: [(String, (ParsedInAppLink) -> Bool)] = [
            ("tg://confirmphone?phone=123&hash=abc", { if case .confirmPhone(_, "123", "abc") = $0 { return true }; return false }),
            ("tg://setlanguage?lang=en", { if case .applyLocalization(_, "en") = $0 { return true }; return false }),
            ("https://t.me/addtheme/night", { if case .theme(_, "night") = $0 { return true }; return false }),
            ("tg://invoice?slug=invoice", { if case .invoice(_, "invoice") = $0 { return true }; return false }),
            ("tg://premium_offer?ref=test", { if case .premiumOffer(_, "test") = $0 { return true }; return false }),
            ("tg://restore_purchases", { if case .restorePurchase = $0 { return true }; return false }),
            ("tg://addlist?slug=folder", { if case .folder(_, "folder") = $0 { return true }; return false }),
            ("tg://boost?channel=123", { if case .boost(_, "_private_123") = $0 { return true }; return false }),
            ("tg://giftcode?slug=gift", { if case .gift(_, "gift") = $0 { return true }; return false }),
            ("tg://message?slug=business", { if case .businessLink(_, "business") = $0 { return true }; return false }),
            ("tg://stars_topup?balance=100&purpose=test", { if case .starsTopup(_, 100, "test") = $0 { return true }; return false }),
            ("tg://premium_multigift", { if case .multigift = $0 { return true }; return false }),
            ("tg://nft?slug=gift", { if case .nft(_, "gift") = $0 { return true }; return false }),
            ("tg://call?slug=call", { if case .joinCall(_, "call") = $0 { return true }; return false }),
            ("tg://stars", { if case .starsInfo(_, false) = $0 { return true }; return false }),
            ("tg://ton", { if case .starsInfo(_, true) = $0 { return true }; return false }),
            ("tg://stargift_auction?slug=gift", { if case .auction(_, "gift") = $0 { return true }; return false }),
            ("tg://oauth?token=token", { if case .oauth(_, "token") = $0 { return true }; return false }),
            ("tg://newbot?manager=owner&username=bot&name=My%20Bot", { if case .createBot(_, "owner", "bot", "My Bot") = $0 { return true }; return false }),
            ("https://t.me/addstyle/style", { if case .addStyle(_, "style") = $0 { return true }; return false })
        ]
        for (url, matches) in cases {
            XCTAssertTrue(matches(parse(url)), "Incorrect payload for \(url)")
        }
    }

    func testBotCreationLinksFollowTheSubmoduleUrlRules() {
        func createBot(_ value: String) -> (manager: String, username: String, title: String?)? {
            guard case let .createBot(_, manager, username, title) = parse(value) else {
                return nil
            }
            return (manager, username, title)
        }

        let full = createBot("https://t.me/newbot/OpenClawBot/durgerkingbot?name=Durger+King")
        XCTAssertEqual(full?.manager, "OpenClawBot")
        XCTAssertEqual(full?.username, "durgerkingbot")
        XCTAssertEqual(full?.title, "Durger King")

        let managerOnly = createBot("https://t.me/newbot/OpenClawBot")
        XCTAssertEqual(managerOnly?.manager, "OpenClawBot")
        XCTAssertEqual(managerOnly?.username, "")
        XCTAssertNil(managerOnly?.title)

        XCTAssertEqual(createBot("https://t.me/newbot/OpenClawBot?name=Durger%20King")?.title, "Durger King")
        XCTAssertEqual(createBot("https://t.me/newbot/OpenClawBot?name=1%2B1")?.title, "1 1")
        XCTAssertNil(createBot("https://t.me/newbot/OpenClawBot?title=Durger")?.title)

        let scheme = createBot("tg://newbot?manager=OpenClawBot&username=durgerkingbot&name=Durger%20King")
        XCTAssertEqual(scheme?.manager, "OpenClawBot")
        XCTAssertEqual(scheme?.username, "durgerkingbot")
        XCTAssertEqual(scheme?.title, "Durger King")

        let schemeManagerOnly = createBot("tg://newbot?manager=OpenClawBot")
        XCTAssertEqual(schemeManagerOnly?.username, "")
        XCTAssertNil(schemeManagerOnly?.title)
        XCTAssertEqual(createBot("tg://newbot?manager=OpenClawBot&name=Durger+King")?.title, "Durger+King")

        XCTAssertNil(createBot("tg://newbot?username=durgerkingbot&name=Durger"))
        XCTAssertNil(createBot("tg://newbot?manager=&username=durgerkingbot"))
        XCTAssertNil(createBot("https://t.me/newbot/"))
        XCTAssertNil(createBot("https://t.me/newbot"))
        if case .createBot = parse("tg://newbot?manager=OpenClawBot", options: InAppLinkParsingOptions()) {
            XCTFail("A bot creation link needs a context")
        }
        if case .createBot = parse("https://t.me/newbot/OpenClawBot", options: InAppLinkParsingOptions()) {
            XCTFail("A bot creation link needs a context")
        }
    }

    func testMalformedAndRepeatedValuesKeepExistingBehavior() {
        assertPeer("tg://resolve?domain=first&domain=last", username: "last")
        assertPeer("tg://resolve?domain=alice&text=hello%2520world", username: "alice", action: .inputText(text: "hello world", behavior: .automatic))
        assertPeer("tg://resolve?domain=alice&post=invalid", username: "alice", post: 0)
        guard case .nothing = parse("tg://stars_topup?balance=invalid&purpose=test") else {
            return XCTFail("Invalid numeric payload must not produce a top-up")
        }
        guard case let .external(value, _) = parse("https://example.com/?text=%ZZ") else {
            return XCTFail("Malformed percent encoding must retain external fallback")
        }
        XCTAssertEqual(value, "https://example.com/?text=%ZZ")
    }

    func testURLHelpersPreserveDecodingAndEmptyFlags() {
        let (values, flags) = urlVars(with: "https://example.com/?TEXT=a%3Db%2520c&text=last&flag&empty=&token=a=b")
        XCTAssertEqual(values["text"], "last")
        XCTAssertEqual(values["empty"], "")
        XCTAssertEqual(values["token"], "a=b")
        XCTAssertEqual(flags, ["flag"])
        XCTAssertEqual(urlVars(with: "text=a%2520b").0["text"], "a%20b")
        XCTAssertEqual(escape(with: "a%20b", addPercent: false), "a b")
        XCTAssertEqual(normalizeURLScheme("TG://resolve?domain=Alice"), "tg://resolve?domain=Alice")
        XCTAssertEqual(explicitUrl("example.com"), "https://example.com")
        XCTAssertEqual(addUrlParameter(value: "x=1", to: "https://example.com"), "https://example.com/x=1")
        XCTAssertEqual(urlWithoutScheme(from: URL(string: "https://example.com/path?q=1#part")!)?.url, "example.com/path?q=1#part")
    }
}
