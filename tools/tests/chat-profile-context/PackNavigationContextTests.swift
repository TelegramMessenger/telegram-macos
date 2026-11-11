extension AccountContext { var meUrlPrefix: String { "https://t.me/" } }
extension String { var nsstring: NSString { self as NSString } }
extension TelegramMediaFile { var customEmojiText: String? { "emoji" } }
extension CommonStrings { var emojiPackPremiumAlert: String { "Premium" } }
enum PremiumBoardingSource { case premiumEmoji }
typealias TelegramPresentationTheme = Int
extension NSAttributedString {
    static func makeAnimated(_ file: TelegramMediaFile, text: String) -> NSAttributedString { NSAttributedString(string: text, attributes: [.init("testFileId"): file.fileId]) }
}
__INPUT_MARKER_HELPER__
final class PackInteraction: FileChatInteraction {
    var presentationIsNormalState = true
    @discardableResult override func appendText(_ text: NSAttributedString, selectedRange: Range<Int>?) -> Range<Int> {
        PackNavigationProbe.check?(); PackNavigationProbe.insertedText.append(text)
        if text.length > 0, let fileId = text.attribute(.init("testFileId"), at: 0, effectiveRange: nil) as? Int64 { PackNavigationProbe.inserted.append(fileId) }
        return 0..<text.length
    }
    func showEmojiUseTooltip() { PackNavigationProbe.check?(); PackNavigationProbe.tooltips += 1 }
}
struct EntertainmentUIHooks {
    static var shared = EntertainmentUIHooks()
    var shareLink: (any AccountContextProtocol, String) -> Void = { _, link in PackNavigationProbe.check?(); PackNavigationProbe.legacyLinks.append(link) }
    var openStickersBot: (any AccountContextProtocol) -> Void = { _ in PackNavigationProbe.check?(); PackNavigationProbe.legacyBots += 1 }
    var currentChatInteraction: (any AccountContextProtocol) -> PackInteraction? = { _ in PackNavigationProbe.check?(); return PackNavigationProbe.interaction }
__PACK_EMOJI_HOOK__
__PACK_STICKER_HOOK__
__PACK_SHARE_HOOK__
__PACK_BOT_HOOK__
}
struct PackPremiumHooks {
    static var shared = PackPremiumHooks()
__PACK_PREMIUM_HOOK__
}
struct ShareLinkObject {
    let link: String
    init(_ context: any AccountContextProtocol, link: String) { PackNavigationProbe.check?(); self.link = link }
}
final class ShareModalController: ViewController {
    let link: String
    init(_ share: ShareLinkObject, analyticsContext: AnalyticsContext) {
        PackNavigationProbe.check?(); self.link = share.link; super.init(); self.analyticsContext = analyticsContext
    }
}
func showModal(with controller: ShareModalController, for window: Int) { PackNavigationProbe.check?(); PackNavigationProbe.shares.append(controller) }
struct PackBotLink { let open: (PeerId, Bool, Int?, Int?) -> Void }
func inApp(for link: NSString, context: AccountContext, openInfo: @escaping (PeerId, Bool, Int?, Int?) -> Void) -> PackBotLink {
    PackNavigationProbe.check?(); PackNavigationProbe.urls.append(link as String); return PackBotLink(open: openInfo)
}
func execute(inapp: PackBotLink, analyticsContext: AnalyticsContext) {
    PackNavigationProbe.check?(); PackNavigationProbe.linkOrigins.append(analyticsContext); PackNavigationProbe.resolved = inapp.open
}
func showModalText(for window: Int, text: String, callback: @escaping (Bool) -> Void) {
    PackNavigationProbe.check?(); PackNavigationProbe.premiumCallback = callback
}
func installPackNavigationBridge() {
    var hooks = EntertainmentUIHooks()
__PACK_NAV_BRIDGES__
    EntertainmentUIHooks.shared = hooks
}
func installPackEmojiBridge() {
    var hooks = EntertainmentUIHooks.shared
__PACK_EMOJI_BRIDGE__
    EntertainmentUIHooks.shared = hooks
}
struct PackNavigationActions {
    let share: (String) -> Void
    let bot: () -> Void
    let emoji: (TelegramMediaFile) -> Void
}
func makePackNavigation(context: any AccountContextProtocol, getAnalyticsContext: @escaping () -> AnalyticsContext) -> PackNavigationActions {
    let close: (() -> Void)? = { PackNavigationProbe.check?(); PackNavigationProbe.closes += 1 }
    let share: (String) -> Void = __PACK_SHARE_CALLBACK__
    let bot: () -> Void = {
__PACK_BOT_CALLBACK__
    }
    let emoji: (TelegramMediaFile) -> Void = __PACK_EMOJI_CALLBACK__
    return PackNavigationActions(share: share, bot: bot, emoji: emoji)
}
enum PackNavigationProbe {
    static var check: (() -> Void)?
    static var shares: [ShareModalController] = []
    static var legacyLinks: [String] = []
    static var legacyBots = 0
    static var urls: [String] = []
    static var linkOrigins: [AnalyticsContext] = []
    static var resolved: ((PeerId, Bool, Int?, Int?) -> Void)?
    static var premiumCallback: ((Bool) -> Void)?
    static var premiums: [(PremiumBoardingSource?, AnalyticsContext)] = []
    static var interaction: PackInteraction? = PackInteraction()
    static var inserted: [Int64] = []
    static var insertedText: [NSAttributedString] = []
    static var tooltips = 0
    static var closes = 0
    static func reset() {
        check = nil; shares = []; legacyLinks = []; legacyBots = 0; urls = []; linkOrigins = []; resolved = nil
        premiumCallback = nil; premiums = []; interaction = PackInteraction(); inserted = []; insertedText = []; tooltips = 0; closes = 0
        Probe.construction = nil; EntertainmentUIHooks.shared = EntertainmentUIHooks(); PackPremiumHooks.shared = PackPremiumHooks()
    }
}
final class PackNavigationContextTests: XCTestCase {
    var context: AccountContext!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        PackNavigationProbe.reset(); PackProbe.reset(); TagProbe.reset(); Analytics.shared = Analytics()
        context = AccountContext(); hub.policy.setOwner(context.account); hub.policy.isEnabled = true
        installPackNavigationBridge()
        PackNavigationProbe.interaction = PackInteraction(context)
        installPackEmojiBridge()
        PackPremiumHooks.shared.showPremiumBoardingWithContext = { _, _, source, openFeatures, theme, origin in
            PackNavigationProbe.check?(); XCTAssertFalse(openFeatures); XCTAssertNil(theme); PackNavigationProbe.premiums.append((source, origin))
        }
    }
    override func tearDown() { PackNavigationProbe.reset(); PackProbe.reset(); TagProbe.reset(); context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.account, privacy: privacy) }
    func actions(_ origin: AnalyticsContext) -> PackNavigationActions {
        var preview: ReactionStickerModal? = StickerPackPreviewModalController(context, peerId: nil, references: [.emoji(42)], analyticsContext: origin)
        let getter = preview!.getOrigin; preview = nil
        return makePackNavigation(context: context, getAnalyticsContext: getter)
    }
    func expectExcluded() {
        PackNavigationProbe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        Probe.construction = PackNavigationProbe.check
    }
    func testShareRetainsOrdinaryOriginAndExactLinkAfterPreviewRelease() {
        let source = origin(); let actions = actions(source)
        actions.share("https://t.me/addemoji/example")
        XCTAssertEqual(PackNavigationProbe.closes, 1); XCTAssertEqual(PackNavigationProbe.shares.first?.link, "https://t.me/addemoji/example")
        XCTAssertTrue(PackNavigationProbe.shares.first?.analyticsContext?.scope === source.scope)
        XCTAssertEqual(PackNavigationProbe.premiums.count, 0); XCTAssertTrue(PackNavigationProbe.urls.isEmpty)
    }
    func testPrivateAndUnknownShareKeepConstructionAndPresentationExcluded() {
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let actions = actions(origin(privacy)); expectExcluded(); actions.share("link")
            XCTAssertTrue(PackNavigationProbe.shares.last!.analyticsContext!.isExcluded)
            XCTAssertFalse(hub.policy.hasExclusions)
        }
        XCTAssertEqual(PackNavigationProbe.shares.count, 2)
    }
    func testAccountSwitchAndRevocationDoNotRenewShareEligibility() {
        let source = origin(); let actions = actions(source)
        hub.policy.setOwner(Account()); expectExcluded(); actions.share("link")
        XCTAssertFalse(PackNavigationProbe.shares.last!.analyticsContext!.scope?.isValid == true)
        hub.policy.setOwner(context.account); actions.share("link")
        XCTAssertFalse(PackNavigationProbe.shares.last!.analyticsContext!.scope?.isValid == true)
    }
    func testLegacyHooksStayFunctionalUnderPrivateGuard() {
        EntertainmentUIHooks.shared = EntertainmentUIHooks()
        let actions = actions(origin(.excluded)); expectExcluded(); actions.share("legacy"); actions.bot()
        XCTAssertEqual(PackNavigationProbe.legacyLinks, ["legacy"]); XCTAssertEqual(PackNavigationProbe.legacyBots, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testOrdinaryBotResolutionPreservesOriginAndDestination() {
        let source = origin(); let actions = actions(source); actions.bot()
        XCTAssertEqual(PackNavigationProbe.urls, ["https://t.me/stickers"])
        XCTAssertTrue(PackNavigationProbe.linkOrigins.first?.scope === source.scope)
        PackNavigationProbe.resolved?(42, false, nil, nil)
        let chat = context.bindings.navigation.pushed.last as! ChatAdditionController
        XCTAssertEqual(chat.interaction.peerId, 42); XCTAssertTrue(chat.analyticsContext?.scope === source.scope)
    }
    func testPrivateBotOriginSurvivesDelayedOrdinaryDestination() {
        let actions = actions(origin(.excluded)); expectExcluded(); actions.bot()
        XCTAssertTrue(PackNavigationProbe.linkOrigins.first!.isExcluded); XCTAssertFalse(hub.policy.hasExclusions)
        PackNavigationProbe.resolved?(42, false, nil, nil)
        XCTAssertTrue(context.bindings.navigation.pushed.last!.analyticsContext!.isExcluded)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testBotRevalidatesAccountAtDelayedResolution() {
        let actions = actions(origin()); actions.bot(); hub.policy.setOwner(Account()); expectExcluded()
        PackNavigationProbe.resolved?(42, false, nil, nil)
        XCTAssertFalse(context.bindings.navigation.pushed.last!.analyticsContext!.scope?.isValid == true)
    }
    func testUnexpectedPrivateBotDestinationRestrictsOrigin() {
        let actions = actions(origin()); actions.bot(); expectExcluded(); PackNavigationProbe.resolved?(-42, false, nil, nil)
        XCTAssertTrue(context.bindings.navigation.pushed.last!.analyticsContext!.isExcluded)
    }
    func testEmojiPremiumCallbackCarriesPrivateOriginAfterPromptReturns() {
        let actions = actions(origin(.excluded)); expectExcluded(); actions.emoji(.init(fileId: 42))
        XCTAssertTrue(PackNavigationProbe.premiums.isEmpty); XCTAssertFalse(hub.policy.hasExclusions)
        PackNavigationProbe.premiumCallback?(true)
        XCTAssertEqual(PackNavigationProbe.premiums.last?.0, .premiumEmoji)
        XCTAssertTrue(PackNavigationProbe.premiums.last!.1.isExcluded)
        XCTAssertTrue(PackNavigationProbe.inserted.isEmpty); XCTAssertEqual(PackNavigationProbe.closes, 0)
    }
    func testEmojiPremiumCallbackRevalidatesAccount() {
        let actions = actions(origin()); actions.emoji(.init(fileId: 42)); hub.policy.setOwner(Account()); expectExcluded()
        PackNavigationProbe.premiumCallback?(true)
        XCTAssertFalse(PackNavigationProbe.premiums.last!.1.scope?.isValid == true)
    }
    func testDisabledAnalyticsDoesNotPreventNavigation() {
        hub.policy.isEnabled = false
        let actions = actions(origin()); expectExcluded(); actions.share("link"); actions.bot(); actions.emoji(.init(fileId: 42))
        PackNavigationProbe.resolved?(42, false, nil, nil); PackNavigationProbe.premiumCallback?(true)
        XCTAssertEqual(PackNavigationProbe.shares.count, 1); XCTAssertEqual(context.bindings.navigation.pushed.count, 1)
        XCTAssertEqual(PackNavigationProbe.premiums.count, 1); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testOrdinaryEmojiInsertionKeepsTextUnmarked() {
        context.isPremium = true
        actions(origin()).emoji(.init(fileId: 42))
        let text = PackNavigationProbe.insertedText.last!
        XCTAssertNil(text.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil))
        XCTAssertEqual(PackNavigationProbe.inserted, [42])
    }
    func testPrivateAndUnknownEmojiInsertionMarksBeforeInputCallback() {
        context.isPremium = true
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let action = actions(origin(privacy)); expectExcluded(); action.emoji(.init(fileId: 42))
            XCTAssertEqual(PackNavigationProbe.insertedText.last!.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) as? Bool, true)
        }
    }
    func testReceivingPrivateComposerMarksOrdinaryEmojiSource() {
        context.isPremium = true
        let action = actions(origin()); PackNavigationProbe.interaction?.privateComposer = true
        action.emoji(.init(fileId: 42))
        XCTAssertEqual(PackNavigationProbe.insertedText.last!.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) as? Bool, true)
    }
    func testLegacyEmojiProviderMarksUnknownComposerProvenance() {
        context.isPremium = true
        EntertainmentUIHooks.shared.appendPackEmojiWithContext = nil
        actions(origin()).emoji(.init(fileId: 42))
        XCTAssertEqual(PackNavigationProbe.insertedText.last!.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) as? Bool, true)
    }
    func testAccountChangedAndDisabledEmojiOriginsCannotPersistEligibility() {
        context.isPremium = true
        let action = actions(origin()); hub.policy.setOwner(Account()); expectExcluded(); action.emoji(.init(fileId: 42))
        XCTAssertEqual(PackNavigationProbe.insertedText.last!.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) as? Bool, true)
        hub.policy.setOwner(context.account); hub.policy.isEnabled = false
        actions(origin()).emoji(.init(fileId: 43))
        XCTAssertEqual(PackNavigationProbe.insertedText.last!.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) as? Bool, true)
    }
    func testPremiumInsertionAndMissingChatKeepExistingBehavior() {
        context.isPremium = true
        let actions = actions(origin(.excluded)); expectExcluded(); actions.emoji(.init(fileId: 42))
        XCTAssertEqual(PackNavigationProbe.inserted, [42]); XCTAssertEqual(PackNavigationProbe.tooltips, 1)
        XCTAssertEqual(PackNavigationProbe.closes, 1); XCTAssertNil(PackNavigationProbe.premiumCallback)
        PackNavigationProbe.interaction?.presentationIsNormalState = false; actions.emoji(.init(fileId: 43))
        PackNavigationProbe.interaction = nil; actions.emoji(.init(fileId: 44))
        XCTAssertEqual(PackNavigationProbe.inserted, [42]); XCTAssertEqual(PackNavigationProbe.closes, 1)
    }
}
