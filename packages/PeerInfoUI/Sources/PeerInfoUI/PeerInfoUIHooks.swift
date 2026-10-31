import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import ChatModeTypes
import AudioPlayerCore

public protocol PeerInfoPremiumConfiguration {
    var minChannelAutotranslationLevel: Int32 { get }
}

@available(macOS 10.15, *)
public struct PeerInfoWalletHooks {
    public let hasWallet: (any AccountContextProtocol) -> Bool
    public let sendMoney: (any AccountContextProtocol, Peer) -> Void
    public let preloadPeerCard: (any AccountContextProtocol, WalletCard) -> Void
    public let showPeerBalance: (any AccountContextProtocol, Peer, (() -> NSView?)?) -> Void

    public var sendMoneyWithContext: ((any AccountContextProtocol, Peer) -> Void)?
    public var showPeerBalanceWithContext: ((any AccountContextProtocol, Peer, (() -> NSView?)?) -> Void)?

    public func sendMoneyObserved(_ context: any AccountContextProtocol, _ peer: Peer) {
        if let sendMoneyWithContext {
            sendMoneyWithContext(context, peer)
        } else {
            sendMoney(context, peer)
        }
    }

    public func showPeerBalanceObserved(_ context: any AccountContextProtocol, _ peer: Peer, _ morphSource: (() -> NSView?)?) {
        if let showPeerBalanceWithContext {
            showPeerBalanceWithContext(context, peer, morphSource)
        } else {
            showPeerBalance(context, peer, morphSource)
        }
    }

    public init(hasWallet: @escaping (any AccountContextProtocol) -> Bool,
                sendMoney: @escaping (any AccountContextProtocol, Peer) -> Void,
                preloadPeerCard: @escaping (any AccountContextProtocol, WalletCard) -> Void,
                showPeerBalance: @escaping (any AccountContextProtocol, Peer, (() -> NSView?)?) -> Void) {
        self.hasWallet = hasWallet
        self.sendMoney = sendMoney
        self.preloadPeerCard = preloadPeerCard
        self.showPeerBalance = showPeerBalance
    }
}

public struct PeerInfoUIHooks {
    public let freezeAlert: (any AccountContextProtocol) -> Void
    public let formatPhoneNumber: (any AccountContextProtocol, String) -> String
    public let resolveUsername: (String, any AccountContextProtocol) -> Signal<Peer?, NoError>
    public let premiumConfiguration: (any AccountContextProtocol) -> any PeerInfoPremiumConfiguration
    public let showDisableSharingModal: (any AccountContextProtocol, PeerId, @escaping (Bool) -> Void) -> Void
    public let showInlineAudioPlayer: (APController, any AccountContextProtocol, TableView?, TableView?) -> Void
    public let showProfileMusicPlayerList: (any AccountContextProtocol, EnginePeer, TelegramMediaFile, ProfileSavedMusicContext.State, ProfileSavedMusicContext) -> Void
    public let activeProfileMusic: (any AccountContextProtocol, PeerId) -> (state: ProfileSavedMusicContext.State, context: ProfileSavedMusicContext, playing: TelegramMediaFile?)?
    public let executeNftLink: (String, String, any AccountContextProtocol) -> Void
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, Atomic<ChatLocationContextHolder?>?) -> Void
    public var navigateToChatWithContext: ((NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, Atomic<ChatLocationContextHolder?>?) -> Void)?
    public func navigateToChatObserved(_ navigation: NavigationViewController?, _ context: any AccountContextProtocol, _ location: ChatLocation, _ mode: ChatMode, _ focus: ChatFocusTarget?, _ holder: Atomic<ChatLocationContextHolder?>?) {
        if let navigateToChatWithContext {
            navigateToChatWithContext(navigation, context, location, mode, focus, holder)
        } else {
            navigateToChat(navigation, context, location, mode, focus, holder)
        }
    }
    public let wallet: Any?

    public init(freezeAlert: @escaping (any AccountContextProtocol) -> Void,
                formatPhoneNumber: @escaping (any AccountContextProtocol, String) -> String,
                resolveUsername: @escaping (String, any AccountContextProtocol) -> Signal<Peer?, NoError>,
                premiumConfiguration: @escaping (any AccountContextProtocol) -> any PeerInfoPremiumConfiguration,
                showDisableSharingModal: @escaping (any AccountContextProtocol, PeerId, @escaping (Bool) -> Void) -> Void,
                showInlineAudioPlayer: @escaping (APController, any AccountContextProtocol, TableView?, TableView?) -> Void,
                showProfileMusicPlayerList: @escaping (any AccountContextProtocol, EnginePeer, TelegramMediaFile, ProfileSavedMusicContext.State, ProfileSavedMusicContext) -> Void,
                activeProfileMusic: @escaping (any AccountContextProtocol, PeerId) -> (state: ProfileSavedMusicContext.State, context: ProfileSavedMusicContext, playing: TelegramMediaFile?)?,
                executeNftLink: @escaping (String, String, any AccountContextProtocol) -> Void,
                navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation, ChatMode, ChatFocusTarget?, Atomic<ChatLocationContextHolder?>?) -> Void,
                wallet: Any?) {
        self.freezeAlert = freezeAlert
        self.formatPhoneNumber = formatPhoneNumber
        self.resolveUsername = resolveUsername
        self.premiumConfiguration = premiumConfiguration
        self.showDisableSharingModal = showDisableSharingModal
        self.showInlineAudioPlayer = showInlineAudioPlayer
        self.showProfileMusicPlayerList = showProfileMusicPlayerList
        self.activeProfileMusic = activeProfileMusic
        self.executeNftLink = executeNftLink
        self.navigateToChat = navigateToChat
        self.wallet = wallet
    }

    @available(macOS 10.15, *)
    public var walletHooks: PeerInfoWalletHooks {
        return wallet as! PeerInfoWalletHooks
    }

    private static var _shared: PeerInfoUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PeerInfoUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PeerInfoUIHooks.install must be called before peer info screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PeerInfoUIHooks) {
        assert(Thread.isMainThread, "PeerInfoUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PeerInfoUIHooks(freezeAlert: { _ in
    }, formatPhoneNumber: { _, number in
        number
    }, resolveUsername: { _, _ in
        .single(nil)
    }, premiumConfiguration: { _ in
        PeerInfoPlaceholderPremiumConfiguration()
    }, showDisableSharingModal: { _, _, _ in
    }, showInlineAudioPlayer: { _, _, _, _ in
    }, showProfileMusicPlayerList: { _, _, _, _, _ in
    }, activeProfileMusic: { _, _ in
        nil
    }, executeNftLink: { _, _, _ in
    }, navigateToChat: { _, _, _, _, _, _ in
    }, wallet: nil)
}

struct PeerInfoPlaceholderPremiumConfiguration: PeerInfoPremiumConfiguration {
    var minChannelAutotranslationLevel: Int32 { return 3 }
}
