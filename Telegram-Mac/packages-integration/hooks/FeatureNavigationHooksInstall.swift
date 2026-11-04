import TelegramContext
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InputDataUI
import PremiumUI
import StarsUI
import DateSelectorUI
import InactiveChannelsUI
import ReportUI
import SessionsUI
import ProxyUI
import InviteLinksUI
import StatisticsUI
import BoostUI
import VerifyAgeUI
import CalendarUI
import SelectCountryUI
import PaymentsUI
import WidgetUI
import InstantPageUI
import WebAppUI
import LocationUI
import ChatExportUI
import GigagroupUI
import CallsUI
import GalleryUI
import PeerInfoUI
import SettingsUI
import ComposeUI
import ShareUI
import ChannelAdminUI
import TelegramCallsCore
import PreviewSenderUI
import ChatUI

private extension PremiumBoardingSource {
    var logSource: PremiumLogEventsSource {
        switch self {
        case .settings: return .settings
        case .noAds: return .no_ads
        case .gracePeriod: return .grace_period
        case .storyViewers: return .story_viewers
        case .storiesStealthMode: return .stories__stealth_mode
        case .storiesSaveToGallery: return .stories__save_to_gallery
        case .premiumStickers: return .premium_stickers
        case .premiumEmoji: return .premium_emoji
        case .storiesQuality: return .stories_quality
        case .savedTags: return .saved_tags
        case .messageEffects: return .message_effects
        case .aiCompose: return .ai_compose
        case .translations: return .translations
        case .noforwards: return .noforwards
        case let .channelBoost(peerId): return .channel_boost(peerId)
        }
    }
}

private extension PremiumLimitKind {
    var limitType: PremiumLimitController.LimitType {
        switch self {
        case .pin: return .pin
        case .pinInArchive: return .pinInArchive
        case .savedGifs: return .savedGifs
        case .folders: return .folders
        case .chatInFolders: return .chatInFolders
        case let .pinInFolders(groupId): return .pinInFolders(groupId)
        case .faveStickers: return .faveStickers
        case .publicLink: return .publicLink
        case .channels: return .channels
        case let .uploadFile(size): return .uploadFile(size)
        case let .caption(length): return .caption(length)
        case let .about(length): return .about(length)
        case let .accounts(count): return .accounts(count)
        case .sharedFolders: return .sharedFolders
        case .sharedInvites: return .sharedInvites
        }
    }
}

private func complicatedReport(_ page: SponsoredReportPage) -> ComplicatedReport {
    return .init(subject: .list(page.options.map { .init(string: $0.text, id: $0.id) }), title: page.title)
}

private func makeFeatureDateSelector(context: any AccountContextProtocol, defaultDate: Date?, repeatPeriod: Int32?, request: DateSelectorRequest, selectedAt: @escaping (Date, Int32?) -> Void) -> DateSelectorModalController {
    let mode: DateSelectorModalController.Mode
    switch request {
    case let .schedule(peerId):
        mode = .schedule(peerId)
    case let .date(title, doneTitle):
        mode = .date(title: title, doneTitle: doneTitle)
    }
    if let defaultDate {
        return DateSelectorModalController(context: context, defaultDate: defaultDate, repeatPeriod: repeatPeriod, mode: mode, selectedAt: selectedAt)
    }
    return DateSelectorModalController(context: context, repeatPeriod: repeatPeriod, mode: mode, selectedAt: selectedAt)
}

func installFeatureNavigationHooks() {
    var hooks = FeatureNavigationHooks()
    hooks.showPremiumBoarding = { context, window, source, openFeatures, presentation in
        prem(with: PremiumBoardingController(context: context, source: (source ?? .settings).logSource, openFeatures: openFeatures, presentation: presentation ?? theme), for: window)
    }
    hooks.showPremiumBoardingWithContext = { context, window, source, openFeatures, presentation in
        prem(with: PremiumBoardingController(context: context, source: (source ?? .settings).logSource, openFeatures: openFeatures, presentation: presentation ?? theme), for: window)
    }
    hooks.showPremiumLimit = { context, kind in
        showPremiumLimit(context: context, type: kind.limitType)
    }
    hooks.showPremiumLimitWithContext = { context, kind in
        if context.isPremium {
            do {
                showPremiumLimit(context: context, type: kind.limitType)
            }
        } else {
            let controller = PremiumLimitController(context: context, type: kind.limitType)
            let onDeinit = controller.onDeinit
            controller.onDeinit = {
                onDeinit?()
            }
            showModal(with: controller, for: context.window)
        }
    }
    hooks.makePremiumLockModal = {
        return PremiumLockModalController()
    }
    hooks.showStarsPurchase = { context, window, currency, suffix, amount in
        showModal(with: Star_ListScreen(context: context, currency: currency, source: .buy(suffix: suffix, amount: amount)), for: window)
    }
    hooks.showStarsPurchaseWithContext = { context, window, currency, suffix, amount in
        let controller = Star_ListScreen(context: context, currency: currency, source: .buy(suffix: suffix, amount: amount))
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        showModal(with: controller, for: window)
    }
    hooks.selectDate = { context, window, defaultDate, repeatPeriod, request, selectedAt in
        let controller = makeFeatureDateSelector(context: context, defaultDate: defaultDate, repeatPeriod: repeatPeriod, request: request, selectedAt: selectedAt)
        showModal(with: controller, for: window)
    }
    hooks.selectDateWithContext = { context, window, defaultDate, repeatPeriod, request, selectedAt, cancelled in
        let controller = makeFeatureDateSelector(context: context, defaultDate: defaultDate, repeatPeriod: repeatPeriod, request: request, selectedAt: selectedAt)
        controller.onCancelled = cancelled
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        showModal(with: controller, for: window)
    }
    hooks.selectDateWithDismissal = { context, window, defaultDate, repeatPeriod, request, selectedAt, cancelled, dismissed in
        let controller = makeFeatureDateSelector(context: context, defaultDate: defaultDate, repeatPeriod: repeatPeriod, request: request, selectedAt: selectedAt)
        controller.onCancelled = cancelled
        controller.onDismissed = dismissed
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        showModal(with: controller, for: window)
    }
    hooks.selectTimeRange = { context, window, from, to, title, ok, fromString, toString, updated in
        showModal(with: TimeRangeSelectorController(context: context, from: from, to: to, title: title, ok: ok, fromString: fromString, toString: toString, updatedValue: updated), for: window)
    }
    hooks.showInactiveChannels = { context, reason in
        let source: InactiveSource
        switch reason {
        case .join: source = .join
        case .create: source = .create
        case .upgrade: source = .upgrade
        }
        showInactiveChannels(context: context, source: source)
    }
    hooks.showInactiveChannelsWithContext = { context, reason in
        let source: InactiveSource
        switch reason {
        case .join: source = .join
        case .create: source = .create
        case .upgrade: source = .upgrade
        }
        showInactiveChannels(context: context, source: source)
    }
    hooks.reportContent = { context, subject, title in
        reportComplicated(context: context, subject: subject, title: title)
    }
    hooks.showSponsoredReport = { context, window, title, info, header, page, report in
        showComplicatedReport(context: context, title: title, info: info, header: header, data: complicatedReport(page), report: { item in
            return report(.init(text: item.string, id: item.id)) |> map { $0.map(complicatedReport) }
        }, window: window)
    }
    hooks.makeRecentSessionsController = { context in
        return RecentSessionsController(context as! AccountContext)
    }
    hooks.makeProxyListController = { context, share, push in
        return proxyListController(accountManager: context.sharedContext.accountManager, network: context.account.network, share: share, pushController: push)
    }
    hooks.makeInviteLinksController = { context, peerId, isChannel in
        return InviteLinksController(context: context, peerId: peerId, isChannel: isChannel, manager: nil)
    }
    hooks.makeRequestJoinMembersController = { context, peerId, manager, openInviteLinks in
        return RequestJoinMemberListController(context: context, peerId: peerId, manager: manager, openInviteLinks: openInviteLinks)
    }
    hooks.showInvitePrivacyLimited = { context, peerId, ids, forbidden in
        showInvitePrivacyLimitedController(context: context, peerId: peerId, ids: ids, forbidden: forbidden)
    }
    hooks.openStoryStats = { context, item, peer in
        context.bindings.rootNavigation().push(MessageStatsController(context, subject: .story(item, peer)))
    }
    hooks.openStoryStatsWithContext = { context, item, peer in
        context.bindings.rootNavigation().push(MessageStatsController(context, subject: .story(item, peer)))
    }
    hooks.showBoostInfo = { context, window, peer, boosts, myStatus, source, presentation in
        let boostSource: BoostChannelSource
        switch source {
        case .story: boostSource = .story
        case .reactions: boostSource = .reactions
        }
        showModal(with: BoostChannelModalController(context: context, peer: peer, boosts: boosts, myStatus: myStatus, infoOnly: true, source: boostSource, presentation: presentation ?? theme), for: window)
    }
    hooks.hasFeatureModal = { kind, modal in
        switch kind {
        case .premiumBoarding:
            return findModal(PremiumBoardingController.self, isAboveTo: modal) != nil
        case .previewSender:
            return findModal(PreviewSenderController.self, isAboveTo: modal) != nil
        }
    }
    hooks.makeVerifyAgeController = { context in
        return VerifyAgeAlertController(context: context)
    }
    hooks.makeCalendarController = { window, current, lowYear, canBeNoYear, select in
        return CalendarController(NSMakeRect(0, 0, 300, 300), window, current: current, lowYear: lowYear, canBeNoYear: canBeNoYear, selectHandler: select)
    }
    hooks.makeSelectCountriesController = { context, selected, complete in
        return SelectCountries(context: context, selected: selected, complete: complete)
    }
    hooks.makePaymentsCheckoutController = { context, source, invoice, completion in
        return PaymentsCheckoutController(context: context, source: source, invoice: invoice, completion: completion.map { completion in
            return { status in
                switch status {
                case .paid: completion(.paid)
                case .cancelled: completion(.cancelled)
                case .failed: completion(.failed)
                }
            }
        })
    }
    hooks.makePaymentsCheckoutControllerWithContext = { context, source, invoice, completion in
        return PaymentsCheckoutController(context: context, source: source, invoice: invoice, completion: completion.map { completion in
            return { status in
                switch status {
                case .paid: completion(.paid)
                case .cancelled: completion(.cancelled)
                case .failed: completion(.failed)
                }
            }
        })
    }
    hooks.emptyChatControllerType = {
        return EmptyChatViewController.self
    }
    hooks.openInstantView = { context, url, webPage in
        BrowserStateContext.get(context).open(tab: .instantView(url: url, webPage: webPage, anchor: nil))
    }
    hooks.requestUserLocation = {
        return requestUserLocation() |> map { result -> UserLocationRequestResult in
            switch result {
            case let .success(location):
                return .success(location)
            }
        } |> `catch` { error -> Signal<UserLocationRequestResult, NoError> in
            switch error {
            case .restricted: return .single(.restricted)
            case .notDetermined: return .single(.notDetermined)
            case .denied: return .single(.denied)
            case .wifiRequired: return .single(.wifiRequired)
            case .disabled: return .single(.disabled)
            }
        }
    }
    hooks.makeLocationPreviewController = { context, address in
        return LocationModalPreview(context, address: address) |> map { $0 as ModalViewController? }
    }
    hooks.fullExportRowTitle = {
        return fullExportRowTitle()
    }
    hooks.fullExportRowInfo = {
        return fullExportRowInfo()
    }
    hooks.showFullExportModal = { context in
        showFullExportModal(context: context)
    }
    hooks.makeGigagroupLandingController = { context, peerId in
        return GigagroupLandingController(context: context, peerId: peerId)
    }
    hooks.openJoinChatBotWebView = { context, botId, url, queryId, joinedPeerId in
        openJoinChatBotWebView(context: context, botId: botId, url: url, queryId: queryId, joinedPeerId: joinedPeerId)
    }
    hooks.openJoinChatBotWebViewWithContext = { context, botId, url, queryId, joinedPeerId in
        openJoinChatBotWebView(context: context, botId: botId, url: url, queryId: queryId, joinedPeerId: joinedPeerId)
    }
    hooks.makeGroupCallAvatarMenuItem = { peer, context in
        return GroupCallAvatarMenuItem(peer, context: context)
    }
    hooks.selectGroupCallJoiner = { context, peerId, completion in
        selectGroupCallJoiner(context: context, peerId: peerId, completion: completion)
    }
    hooks.makeLinkInvitationController = { context, peerId in
        return LinkInvationController(context as! AccountContext, peerId: peerId)
    }
    hooks.makeTwoStepAccessController = { context, present in
        return twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController: { value in
            present(value.controller, value.root, value.animated)
        })
    }
    hooks.createSupergroup = { context, defaultText in
        return createSupergroup(with: context as! AccountContext, defaultText: defaultText)
    }
    hooks.shareLink = { context, window, link in
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: window)
    }
    hooks.makeChannelAdminController = { context, peerId, adminId, initialParticipant, updated, upgradedToSupergroup in
        return ChannelAdminModalController(context as! AccountContext, peerId: peerId, adminId: adminId, initialParticipant: initialParticipant, updated: updated, upgradedToSupergroup: upgradedToSupergroup)
    }
    hooks.makeChannelAdminControllerWithContext = { context, peerId, adminId, initialParticipant, updated, upgradedToSupergroup in
        return ChannelAdminModalController(context as! AccountContext, peerId: peerId, adminId: adminId, initialParticipant: initialParticipant, updated: updated, upgradedToSupergroup: upgradedToSupergroup)
    }
    hooks.applyGroupCallResult = { sharedContext, callContext in
        GroupCallUIHooks.shared.applyGroupCallResult(sharedContext, callContext as! (any GroupCallContextProtocol))
    }
    hooks.makeArchiveSettingsController = { context, privacy, update in
        return ArchiveSettingsController(context: context, privacy: privacy, update: update)
    }
    hooks.updateAccountBirthday = { date, context in
        editAccountUpdateBirthday(date, context: context)
    }
    hooks.makePreviewSender = { urls, interaction, asMedia, attributedString, presentation in
        guard let interaction = interaction as? ChatInteraction else { return nil }
        return PreviewSenderController(urls: urls, chatInteraction: interaction, asMedia: asMedia, attributedString: attributedString, presentation: presentation)
    }
    hooks.makePreviewSenderWithContext = { urls, interaction, asMedia, attributedString, presentation in
        guard let interaction = interaction as? ChatInteraction else { return nil }
        return PreviewSenderController(urls: urls, chatInteraction: interaction, asMedia: asMedia, attributedString: attributedString, presentation: presentation)
    }
    FeatureNavigationHooks.install(hooks)
}
