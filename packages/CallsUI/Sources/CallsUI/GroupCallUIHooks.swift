import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramCallsCore
import TelegramTheme
import GeneralRows

public protocol GroupCallAvatarData {
    var peer: Peer { get }
    var state: GroupCallParticipantsContext.Participant? { get }
    var isSpeaking: Bool { get }
}

public enum GroupCallJoinResult {
    case success(any GroupCallContextProtocol)
    case fail
    case samePeer(any GroupCallContextProtocol)
}

public struct GroupCallUIHooks {
    public let groupCallThemeMembersColor: () -> NSColor
    public let groupCallThemeGrayStatusColor: () -> NSColor
    public let groupCallThemeSpeakInactiveColor: () -> NSColor
    public let groupCallThemeSpeakLockedColor: () -> NSColor
    public let groupCallThemeSpeakDisabledColor: () -> NSColor
    public let groupCallThemeCustomTheme: () -> GeneralRowItem.Theme
    public let groupCallThemeInviteIcon: () -> CGImage
    public let groupCallThemeShareIcon: () -> CGImage
    public let requestOrJoinConferenceCall: (any AccountContextProtocol, GroupCallInfo, InternalGroupCallReference) -> Signal<GroupCallJoinResult, NoError>
    public let applyGroupCallResult: (any SharedAccountContextProtocol, any GroupCallContextProtocol) -> Void
    public let makeRTMPStartController: (any AccountContextProtocol, PeerId, Date?, @escaping (PeerId, Date?, Bool) -> Void) -> ModalViewController
    public let makeShareLinkModal: (any AccountContextProtocol, String, TelegramPresentationTheme, Set<PeerId>) -> ModalViewController

    public init(groupCallThemeMembersColor: @escaping () -> NSColor,
                groupCallThemeGrayStatusColor: @escaping () -> NSColor,
                groupCallThemeSpeakInactiveColor: @escaping () -> NSColor,
                groupCallThemeSpeakLockedColor: @escaping () -> NSColor,
                groupCallThemeSpeakDisabledColor: @escaping () -> NSColor,
                groupCallThemeCustomTheme: @escaping () -> GeneralRowItem.Theme,
                groupCallThemeInviteIcon: @escaping () -> CGImage,
                groupCallThemeShareIcon: @escaping () -> CGImage,
                requestOrJoinConferenceCall: @escaping (any AccountContextProtocol, GroupCallInfo, InternalGroupCallReference) -> Signal<GroupCallJoinResult, NoError>,
                applyGroupCallResult: @escaping (any SharedAccountContextProtocol, any GroupCallContextProtocol) -> Void,
                makeRTMPStartController: @escaping (any AccountContextProtocol, PeerId, Date?, @escaping (PeerId, Date?, Bool) -> Void) -> ModalViewController,
                makeShareLinkModal: @escaping (any AccountContextProtocol, String, TelegramPresentationTheme, Set<PeerId>) -> ModalViewController) {
        self.groupCallThemeMembersColor = groupCallThemeMembersColor
        self.groupCallThemeGrayStatusColor = groupCallThemeGrayStatusColor
        self.groupCallThemeSpeakInactiveColor = groupCallThemeSpeakInactiveColor
        self.groupCallThemeSpeakLockedColor = groupCallThemeSpeakLockedColor
        self.groupCallThemeSpeakDisabledColor = groupCallThemeSpeakDisabledColor
        self.groupCallThemeCustomTheme = groupCallThemeCustomTheme
        self.groupCallThemeInviteIcon = groupCallThemeInviteIcon
        self.groupCallThemeShareIcon = groupCallThemeShareIcon
        self.requestOrJoinConferenceCall = requestOrJoinConferenceCall
        self.applyGroupCallResult = applyGroupCallResult
        self.makeRTMPStartController = makeRTMPStartController
        self.makeShareLinkModal = makeShareLinkModal
    }

    private static var _shared: GroupCallUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GroupCallUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("GroupCallUIHooks.install must be called before group call screens are used")
        return .placeholder
    }

    public static func install(_ hooks: GroupCallUIHooks) {
        assert(Thread.isMainThread, "GroupCallUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = GroupCallUIHooks(groupCallThemeMembersColor: {
        NSColor.clear
    }, groupCallThemeGrayStatusColor: {
        NSColor.clear
    }, groupCallThemeSpeakInactiveColor: {
        NSColor.clear
    }, groupCallThemeSpeakLockedColor: {
        NSColor.clear
    }, groupCallThemeSpeakDisabledColor: {
        NSColor.clear
    }, groupCallThemeCustomTheme: {
        GeneralRowItem.Theme()
    }, groupCallThemeInviteIcon: {
        generateImage(NSMakeSize(1, 1), rotatedContext: { size, ctx in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        })!
    }, groupCallThemeShareIcon: {
        generateImage(NSMakeSize(1, 1), rotatedContext: { size, ctx in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        })!
    }, requestOrJoinConferenceCall: { _, _, _ in
        .single(.fail)
    }, applyGroupCallResult: { _, _ in
    }, makeRTMPStartController: { _, _, _, _ in
        ModalViewController()
    }, makeShareLinkModal: { _, _, _, _ in
        ModalViewController()
    })
}
