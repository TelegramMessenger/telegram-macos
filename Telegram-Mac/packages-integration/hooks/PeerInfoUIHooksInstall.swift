import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import WalletContext
import AudioPlayerUI
import AudioPlayerCore
import PeerInfoUI
import QrStudioUI

extension PremiumConfiguration: PeerInfoPremiumConfiguration {

}

private func makePeerInfoWalletHooks() -> Any? {
    if #available(macOS 10.15, *) {
        var hooks = PeerInfoWalletHooks(hasWallet: { context in
            return (context as! AccountContext).walletContext != nil
        }, sendMoney: { context, peer in
            let context = context as! AccountContext
            guard let walletContext = context.walletContext else {
                return
            }
            showWalletSendMoney(context: context, walletContext: walletContext, peer: peer)
        }, preloadPeerCard: { context, card in
            preloadWalletPeerCard(context: context as! AccountContext, card: card)
        }, showPeerBalance: { context, peer, morphSource in
            let context = context as! AccountContext
            guard let walletContext = context.walletContext else {
                return
            }
            showWalletPeerBalance(context: context, walletContext: walletContext, peer: peer, morphSource: morphSource)
        })
        hooks.sendMoneyWithContext = { context, peer in
            let context = context as! AccountContext
            guard let walletContext = context.walletContext else { return }
            showWalletSendMoney(context: context, walletContext: walletContext, peer: peer)
        }
        hooks.showPeerBalanceWithContext = { context, peer, morphSource in
            let context = context as! AccountContext
            guard let walletContext = context.walletContext else { return }
            showWalletPeerBalance(context: context, walletContext: walletContext, peer: peer, morphSource: morphSource)
        }
        return hooks
    } else {
        return nil
    }
}

private func makePeerInfoNavigationHooks() -> PeerInfoNavigationHooks {
    var hooks = PeerInfoNavigationHooks()
    hooks.openQrStudio = { context, peerId, morphSource in
        showQrStudio(context: context, peerId: peerId, morphSource: morphSource)
    }
    hooks.openQrStudioWithContext = { context, peerId, morphSource in
        showQrStudio(context: context, peerId: peerId, morphSource: morphSource)
    }
    hooks.prefetchQrStudio = { context, peer in
        prefetchQrStudio(context: context, peer: peer)
    }
    hooks.makeGroupsInCommonController = { context, peerId in
        return GroupsInCommonViewController(context: context as! AccountContext, peerId: peerId)
    }
    hooks.makeGroupsInCommonControllerWithContext = { context, peerId in
        return GroupsInCommonViewController(context: context, peerId: peerId)
    }
    hooks.showTranslateModal = { context, fromLang, toLang, text in
        let context = context as! AccountContext
        showModal(with: TranslateModalController(context: context, from: fromLang, toLang: toLang, text: text), for: context.window)
    }
    hooks.makeChannelVisibilityController = { context, peerId, isChannel, linksManager in
        let context = context as! AccountContext
        let setup: ChannelVisibilityController
        if let linksManager {
            setup = ChannelVisibilityController(context, peerId: peerId, isChannel: isChannel, linksManager: linksManager)
        } else {
            setup = ChannelVisibilityController(context, peerId: peerId, isChannel: isChannel)
        }
        return (setup, setup.onComplete.get())
    }
    hooks.makeChannelDiscussionSetupController = { context, peer in
        return ChannelDiscussionSetupController(context: context as! AccountContext, peer: peer)
    }
    hooks.makeWelcomeMessageController = { context, peerId in
        return WelcomeMessageController(context: context as! AccountContext, peerId: peerId)
    }
    hooks.makeGroupStickerSetController = { context, peerId in
        return GroupStickerSetController(context as! AccountContext, peerId: peerId)
    }
    hooks.makeGroupReactionsSettingsController = { context, peerId, allowedReactions, availableReactions in
        return ReactionsSettingsController(context: context as! AccountContext, peerId: peerId, allowedReactions: allowedReactions, availableReactions: availableReactions, mode: .chat(isGroup: true))
    }
    hooks.showChannelReactions = { context, peerId, allowedReactions, availableReactions, reactionsCount, starsAllowed in
        let context = context as! AccountContext
        showModal(with: ChannelReactionsController(context: context, peerId: peerId, allowedReactions: allowedReactions, availableReactions: availableReactions, reactionsCount: reactionsCount, starsAllowed: starsAllowed), for: context.window)
    }
    hooks.makeSuggestPostController = { context, peerId in
        return SuggestPostController(context: context as! AccountContext, peerId: peerId)
    }
    hooks.makeForumTopicEditController = { context, peerId, threadData, threadId in
        return ForumTopicInfoController(context: context as! AccountContext, purpose: .edit(threadData, threadId), peerId: peerId)
    }
    hooks.makeForumSettingsController = { context, peerId in
        return ForumSettingsController(context: context as! AccountContext, peerId: peerId)
    }
    hooks.openFragment = { context, peerId, subject, copy in
        let context = context as! AccountContext
        let fragmentSubject: FragmentItemInfoScreenSubject
        switch subject {
        case let .username(value):
            fragmentSubject = .username(value)
        case let .phoneNumber(value):
            fragmentSubject = .phoneNumber(value)
        }
        _ = showModalProgress(signal: FragmentItemInitialData(context: context, peerId: peerId, subject: fragmentSubject), for: context.window).startStandalone(next: { data in
            if let data {
                showModal(with: FragmentUsernameController(context: context, data: data), for: context.window)
            } else {
                switch subject {
                case let .phoneNumber(value):
                    copy(formatPhoneNumber(context: context, number: value))
                case let .username(value):
                    copy("@\(value)")
                }
            }
        })
    }
    hooks.makeStarMonetizationController = { context, peerId, revenueContext in
        return FragmentStarMonetizationController(context: context as! AccountContext, peerId: peerId, revenueContext: revenueContext)
    }
    hooks.makeTonMonetizationController = { context, peerId, revenueContext in
        return FragmentMonetizationController(context: context as! AccountContext, peerId: peerId, onlyTonContext: revenueContext)
    }
    hooks.showRestrictMember = { context, peerId, memberId, participant, updated in
        let context = context as! AccountContext
        showModal(with: RestrictedModalController(context, peerId: peerId, memberId: memberId, initialParticipant: participant, updated: updated), for: context.window)
    }
    hooks.showChannelParticipant = { context, peerId, participant in
        let context = context as! AccountContext
        showModal(with: ChannelParticipantController(context: context, peerId: peerId, participant: participant), for: context.window)
    }
    hooks.showRestrictMemberWithContext = { context, peerId, memberId, participant, updated in
        showModal(with: RestrictedModalController(context, peerId: peerId, memberId: memberId, initialParticipant: participant, updated: updated), for: context.window)
    }
    hooks.showChannelParticipantWithContext = { context, peerId, participant in
        showModal(with: ChannelParticipantController(context: context as! AccountContext, peerId: peerId, participant: participant), for: context.window)
    }
    hooks.makeChannelMembersController = { context, peerId in
        return ChannelMembersViewController(context as! AccountContext, peerId: peerId)
    }
    hooks.makeChannelBlacklistController = { context, peerId in
        return ChannelBlacklistViewController(context as! AccountContext, peerId: peerId)
    }
    hooks.makeChannelPermissionsController = { context, peerId in
        return ChannelPermissionsController(context as! AccountContext, peerId: peerId)
    }
    hooks.showUserTagInfo = { context, tag, authorName, groupName, badgeType, canEditRank in
        let context = context as! AccountContext
        let configuration = UserTagInfoConfiguration(tag: tag, authorName: authorName, groupName: groupName, badgeType: badgeType, canEditRank: canEditRank)
        showModal(with: UserTagInfoModalController(context: context, configuration: configuration), for: context.window)
    }
    hooks.showUserTagInfoWithContext = { context, tag, authorName, groupName, badgeType, canEditRank in
        let configuration = UserTagInfoConfiguration(tag: tag, authorName: authorName, groupName: groupName, badgeType: badgeType, canEditRank: canEditRank)
        showModal(with: UserTagInfoModalController(context: context, configuration: configuration), for: context.window)
    }
    hooks.makeSelectColorController = { context, peer in
        return SelectColorController(context: context as! AccountContext, peer: peer)
    }
    hooks.peerColorsLabelIcon = { peer, context in
        return generateSettingsMenuPeerColorsLabelIcon(peer: peer, context: context)
    }
    hooks.editAccountInfo = { context, f in
        EditAccountInfoController(context: context as! AccountContext, f: f)
    }
    return hooks
}

func installPeerInfoUIHooks() {
    PeerInfoNavigationHooks.install(makePeerInfoNavigationHooks())

    var hooks = PeerInfoUIHooks(freezeAlert: { context in
        (context as! AccountContext).freezeAlert()
    }, formatPhoneNumber: { context, number in
        return formatPhoneNumber(context: context as! AccountContext, number: number)
    }, resolveUsername: { username, context in
        return resolveUsername(username: username, context: context as! AccountContext)
    }, premiumConfiguration: { context in
        return PremiumConfiguration.with(appConfiguration: context.appConfiguration)
    }, showDisableSharingModal: { context, peerId, toggle in
        showDisableSharingModal(context: context as! AccountContext, peerId: peerId, toggle: toggle)
    }, showInlineAudioPlayer: { controller, context, tableView, supportTableView in
        let context = context as! AccountContext
        let object = InlineAudioPlayerView.ContextObject(controller: controller, context: context, tableView: tableView, supportTableView: supportTableView)
        context.sharedContext.showInlinePlayer(object)
    }, showProfileMusicPlayerList: { context, peer, musicFile, savedMusic, profileSavedMusic in
        let context = context as! AccountContext
        guard let playerView = context.bindings.rootNavigation().header?.view as? InlineAudioPlayerView else {
            return
        }
        showModal(with: PlayerListController(audioPlayer: playerView, context: context, currentContext: context, source: .profile(peer, musicFile, savedMusic, profileSavedMusic)), for: context.window)
    }, activeProfileMusic: { context, peerId in
        let context = context as! AccountContext
        guard context.bindings.rootNavigation().header?.contextObject is InlineAudioPlayerView.ContextObject, let controller = context.sharedContext.getAudioPlayer() as? APProfileSavedController, controller.peer.id == peerId, controller.account.id == context.account.id, let state = controller.currentState else {
            return nil
        }
        var playing: TelegramMediaFile?
        if let entry = controller.currentSong?.entry, case let .savedMusic(reference, _) = entry {
            playing = reference.media
        }
        return (state, controller.profileMusicContext, playing)
    }, executeNftLink: { link, slug, context in
        execute(inapp: .nft(link: link, slug: slug, context: context as! AccountContext))
    }, navigateToChat: { navigation, context, chatLocation, mode, focusTarget, chatLocationContextHolder in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation, mode: mode, focusTarget: focusTarget, chatLocationContextHolder: chatLocationContextHolder)
    }, wallet: makePeerInfoWalletHooks())
    hooks.navigateToChatWithContext = { navigation, context, location, mode, focus, holder in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: location, mode: mode, focusTarget: focus, chatLocationContextHolder: holder)
    }
    PeerInfoUIHooks.install(hooks)
}
