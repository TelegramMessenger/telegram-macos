import Cocoa
import TGUIKit
import TelegramCore

import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramLinks
import TelegramMediaUtils
import Localization
import InAppSettings
import AlertsUI
import SceneEffects
import ChatHistoryModel
import ChatUI
import StoriesUI
import BoostUI
import StatisticsUI
import ChannelAdminUI
import CallsUI
import GroupCallScreenUI
import WebAppUI
import InlineStickerLayer

struct UserInfoPersonalChannel : Equatable {
    let peer: EnginePeer
    let message: EngineMessage?
    let subscribers: Int32?
}


class PeerInfoArguments<Context: AccountContextProtocol> {
    let peerId:PeerId
    let context: Context
    let isAd: Bool
    let pushViewController:(ViewController) -> Void
    private let avatarExpandedLock = NSLock()
    private var avatarExpandedValue: Bool = false
    var isAvatarExpanded: Bool {
        get {
            avatarExpandedLock.lock()
            defer { avatarExpandedLock.unlock() }
            return avatarExpandedValue
        }
        set {
            avatarExpandedLock.lock()
            avatarExpandedValue = newValue
            avatarExpandedLock.unlock()
        }
    }
    
    var peer: Peer? {
        didSet {
            var bp = 0
            bp += 1
        }
    }
    
    var effectivePeerId: PeerId {
        if let peer = peer as? TelegramSecretChat {
            return peer.associatedPeerId ?? peerId
        } else {
            return peer?.id ?? peerId
        }
    }
    
    let pullNavigation:()->NavigationViewController?
    let mediaController: ()->PeerMediaController<Context>?
    
    let getStarsContext:(()->StarsRevenueStatsContext?)?
    let getTonContext:(()->StarsRevenueStatsContext?)?
    let getStarGiftsContext:(()->ProfileGiftsContext?)?
    let getSavedMusicContext:(()->ProfileSavedMusicContext?)?

    
    let toggleNotificationsDisposable = MetaDisposable()
    private let deleteDisposable = MetaDisposable()

    func openQrStudio(from control: NSView) {
        PeerInfoNavigationHooks.shared.openQrStudioObserved(context, peerId, { [weak control] in control })
    }
    private let _statePromise = Promise<PeerInfoState>()
    
    var statePromise:Signal<PeerInfoState, NoError> {
        return _statePromise.get()
    }
    
    private let value:Atomic<PeerInfoState>
    
    var state:PeerInfoState {
        return value.modify {$0}
    }
    
    func updateInfoState(_ f: (PeerInfoState) -> PeerInfoState) -> Void {
        _statePromise.set(.single(value.modify(f)))
    }
    
    func copy(_ string: String) {
        copyToClipboard(string)
        showModalText(for: context.window, text: strings().shareLinkCopied)
    }
    
    func archiveStories() {
        self.pushViewController(StoryMediaController(context: context, peerId: peerId, listContext: PeerStoryListContext(account: context.account, peerId: peerId, isArchived: true, folderId: nil), standalone: true, isArchived: true))
    }
    
    func blocked() -> Void {
        pushViewController(PeerInfoNavigationHooks.shared.makeChannelBlacklistController(context, peerId))
    }
    
    func boosts(_ access: GroupAccess) {
        let context = self.context
        
        if access.isCreator || self.peer?.isAdmin == true {
            self.pushViewController(ChannelBoostStatsController(context: context, peerId: peerId, isGroup: true))
        } else {
            let signal: Signal<(Peer, ChannelBoostStatus?, MyBoostStatus?)?, NoError> = context.account.postbox.loadedPeerWithId(peerId) |> mapToSignal { value in
                return combineLatest(context.engine.peers.getChannelBoostStatus(peerId: value.id), context.engine.peers.getMyBoostStatus()) |> map {
                    (value, $0, $1)
                }
            }
            _ = showModalProgress(signal: signal, for: context.window).start(next: { value in
                if let value = value, let boosts = value.1 {
                    showModal(with: BoostChannelModalController(context: context, peer: value.0, boosts: boosts, myStatus: value.2), for: context.window)
                } else {
                    alert(for: context.window, info: strings().unknownError)
                }
            })
        }
    }
    
    func enableTranslate() {
        let peerId = self.peerId
        _ = context.engine.messages.togglePeerMessagesTranslationHidden(peerId: peerId, hidden: false).start()
        
        let chat = self.pullNavigation()?.first({ $0 is ChatController<Context> }) as? ChatController<Context>
        chat?.chatInteraction.toggleTranslate()
        
        self.pullNavigation()?.back()

    }
    
    func eventLog() {
        let context = self.context
        let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue
        _ = signal.startStandalone(next: { [weak self] peer in
            if let peer {
                self?.pullNavigation()?.push(ChannelEventLogController(context, peer: peer))
            }
        })
    }
    
    func makeVoiceChat(_ current: CachedChannelData.ActiveCall?, callJoinPeerId: PeerId?) {
        let context = self.context
        let peerId = self.peerId
        if let activeCall = current {
            let join:(PeerId, Date?, Bool)->Void = { joinAs, _, _ in
                _ = requestOrJoinGroupCall(context: context, peerId: peerId, joinAs: joinAs, initialCall: activeCall, initialInfo: nil, joinHash: nil, reference: nil).start(next: { result in
                    switch result {
                    case let .samePeer(callContext), let .success(callContext):
                        applyGroupCallResult(context.sharedContext, callContext)
                    default:
                        alert(for: context.window, info: strings().errorAnError)
                    }
                })
            }
            if let callJoinPeerId = callJoinPeerId {
                join(callJoinPeerId, nil, false)
            } else {
                selectGroupCallJoiner(context: context, peerId: peerId, completion: join)
            }
        } else {
            createVoiceChat(context: context, peerId: peerId, canBeScheduled: true)
        }
    }
    
    func openNameColor(peer: Peer) {
        pushViewController(PeerInfoNavigationHooks.shared.makeSelectColorController(context, peer))
    }
    
    func openStats(canSeeTon: Bool, canSeeStars: Bool) {
        self.pushViewController(ChannelStatsSegmentController(context, peerId: peerId, isChannel: true, monetization: canSeeTon, stars: canSeeStars && !canSeeTon, onlyMonetization: true))
    }
    
    func openWelcomeMessages() {
        pushViewController(PeerInfoNavigationHooks.shared.makeWelcomeMessageController(context, peerId))
    }
    
    func setupDiscussion() {
        _ = (self.context.account.postbox.loadedPeerWithId(self.peerId) |> deliverOnMainQueue).start(next: { [weak self] peer in
            if let `self` = self {
                self.pushViewController(PeerInfoNavigationHooks.shared.makeChannelDiscussionSetupController(self.context, peer))
            }
        })
    }
    
    func updateEditable(_ editable:Bool, peerView:PeerView, controller: PeerInfoController<Context>) -> Bool {
        return true
    }
    
    func dismissEdition() {
        
    }
    
    func peerInfo(_ peerId:PeerId) {
        if let navigation = pullNavigation() {
            PeerInfoController<Context>.push(navigation: navigation, context: context, peerId: peerId)
        }
    }
    
    func peerChat(_ peerId:PeerId, postId: MessageId? = nil) {
        pushViewController(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: postId)))
    }
    
    func openStory(_ initialId: StoryInitialIndex?) {
        StoryModalController<Context>.ShowStories(context: context, isHidden: false, initialId: initialId, singlePeer: true)
    }
    
    func openFragment(_ subject: PeerInfoFragmentSubject) {
        PeerInfoNavigationHooks.shared.openFragment(context, peerId, subject, { [weak self] text in
            self?.copy(text)
        })
    }
    
    func toggleNotifications(_ currentlyMuted: Bool) {
        
        toggleNotificationsDisposable.set(context.engine.peers.togglePeerMuted(peerId: effectivePeerId, threadId: nil).start())
        
        showModalText(for: context.window, text: currentlyMuted ? strings().toastUnmuted : strings().toastMuted)
    }
    
    func delete() {
        self.delete(force: false)
    }
    
    func delete(force: Bool) {
        let context = self.context
        let peerId = self.peerId
        
        let isEditing = (state as? GroupInfoState)?.editingState != nil || (state as? ChannelInfoState)?.editingState != nil || force
        
        let signal = context.account.postbox.peerView(id: peerId) |> take(1) |> mapToSignal { view -> Signal<Bool, NoError> in
            return removeChatInteractively(context: context, peerId: peerId, userId: peerViewMainPeer(view)?.id, deleteGroup: isEditing && peerViewMainPeer(view)?.groupAccess.isCreator == true, forceRemoveGlobally: isEditing && peerViewMainPeer(view)?.groupAccess.isCreator == true)
        } |> deliverOnMainQueue
        
        deleteDisposable.set(signal.start(next: { [weak self] result in
            if result {
                self?.pullNavigation()?.close()
            }
        }))
    }
    
    func sharedMedia() {
        if let controller = self.mediaController() {
            pushViewController(controller)
        }
    }
    
    init(context: Context, peerId:PeerId, state:PeerInfoState, isAd: Bool, pushViewController:@escaping(ViewController)->Void, pullNavigation:@escaping()->NavigationViewController?, mediaController: @escaping()->PeerMediaController<Context>?, getStarsContext: (()->StarsRevenueStatsContext?)? = nil, getTonContext: (()->StarsRevenueStatsContext?)? = nil, getStarGiftsContext: (()->ProfileGiftsContext?)? = nil, getSavedMusicContext: (()->ProfileSavedMusicContext?)? = nil) {
        self.value = Atomic(value: state)
        _statePromise.set(.single(state))
        self.context = context
        self.peerId = peerId
        self.isAd = isAd
        self.pushViewController = pushViewController
        self.pullNavigation = pullNavigation
        self.mediaController = mediaController
        self.getStarsContext = getStarsContext
        self.getTonContext = getTonContext
        self.getStarGiftsContext = getStarGiftsContext
        self.getSavedMusicContext = getSavedMusicContext
    }

    
    deinit {
        toggleNotificationsDisposable.dispose()
        deleteDisposable.dispose()
    }
}


struct TemporaryParticipant: Equatable {
    let peer: Peer
    let presence: PeerPresence?
    let timestamp: Int32
    
    static func ==(lhs: TemporaryParticipant, rhs: TemporaryParticipant) -> Bool {
        if !lhs.peer.isEqual(rhs.peer) {
            return false
        }
        if let lhsPresence = lhs.presence, let rhsPresence = rhs.presence {
            if !lhsPresence.isEqual(to: rhsPresence) {
                return false
            }
        } else if (lhs.presence != nil) != (rhs.presence != nil) {
            return false
        }
        return true
    }
}

private struct PeerInfoSortableStableId: Hashable {
    let id: PeerInfoEntryStableId
    
    static func ==(lhs: PeerInfoSortableStableId, rhs: PeerInfoSortableStableId) -> Bool {
        return lhs.id.isEqual(to: rhs.id)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id.hashValue)
    }
    
}

private struct PeerInfoSortableEntry: Identifiable, Comparable {
    let entry: PeerInfoEntry
    
    var stableId: PeerInfoSortableStableId {
        return PeerInfoSortableStableId(id: self.entry.stableId)
    }
    
    static func ==(lhs: PeerInfoSortableEntry, rhs: PeerInfoSortableEntry) -> Bool {
        return lhs.entry.isEqual(to: rhs.entry)
    }
    
    static func <(lhs: PeerInfoSortableEntry, rhs: PeerInfoSortableEntry) -> Bool {
        return lhs.entry.isOrderedBefore(rhs.entry)
    }
}

struct PeerMediaTabsData : Equatable {
    let collections:[PeerMediaCollectionMode]
    let loaded: Bool
}


fileprivate func prepareEntries<Context: AccountContextProtocol>(from:[AppearanceWrapperEntry<PeerInfoSortableEntry>]?, to:[AppearanceWrapperEntry<PeerInfoSortableEntry>], account:Account, initialSize:NSSize, peerId:PeerId, arguments: PeerInfoArguments<Context>, animated:Bool) -> Signal<TableUpdateTransition, NoError> {
    
    return Signal { subscriber in
        
        var cancelled = false
        
        if Thread.isMainThread {
            var initialIndex:Int = 0
            var height:CGFloat = 0
            var firstInsertion:[(Int, TableRowItem)] = []
            let entries = Array(to)
            
            let index:Int = 0
            
            for i in index ..< entries.count {
                let item = entries[i].entry.entry.item(initialSize: initialSize, arguments: arguments)
                height += item.height
                firstInsertion.append((i, item))
                if initialSize.height < height {
                    break
                }
            }
            
            
            initialIndex = firstInsertion.count
            subscriber.putNext(TableUpdateTransition(deleted: [], inserted: firstInsertion, updated: [], state: .none(nil)))
            
            prepareQueue.async {
                if !cancelled {
                    var insertions:[(Int, TableRowItem)] = []
                    let updates:[(Int, TableRowItem)] = []
                    
                    for i in initialIndex ..< entries.count {
                        let item:TableRowItem
                        item = entries[i].entry.entry.item(initialSize: initialSize, arguments: arguments)
                        insertions.append((i, item))
                    }
                    subscriber.putNext(TableUpdateTransition(deleted: [], inserted: insertions, updated: updates, state: .none(nil)))
                    subscriber.putCompletion()
                }
            }
        } else {
            let (deleted,inserted, updated) = proccessEntriesWithoutReverse(from, right: to, { (peerInfoSortableEntry) -> TableRowItem in
                return peerInfoSortableEntry.entry.entry.item(initialSize: initialSize, arguments: arguments)
            })
            
            subscriber.putNext(TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, state: animated ? .none(nil) : .saveVisible(.lower, false), grouping: true, animateVisibleOnly: false))
            subscriber.putCompletion()
        }
        
        return ActionDisposable {
            cancelled = true
        }
    }
    
    
}

public final class PeerInfoView<Context: AccountContextProtocol> : View {
    let tableView: TableView
    let navigationBarView = NavigationBarView(frame: .zero)
    private let navBgView = View()
    private var navigationOverflow: CGFloat = 0
    public required init(frame frameRect: NSRect) {
        tableView = .init(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(navBgView)
        addSubview(navigationBarView)
        updateEdgeShadowOpacity(0)
                
    }
    
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        tableView.enumerateItems(with: { item in
            if let item = item as? PeerInfoHeadItem<Context> {
                item.view?.mouseDown(with: event)
                return false
            }
            return true
        })
        
    }
    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        
        tableView.enumerateItems(with: { item in
            if let item = item as? PeerInfoHeadItem<Context> {
                item.view?.mouseUp(with: event)
                return false
            }
            return true
        })
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: navigationBarView, frame: NSMakeRect(0, navigationOverflow, size.width, 64))
        transition.updateFrame(view: navBgView, frame: navigationBarView.frame)
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, 0, size.width, size.height))
    }

    func updateNavigationOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        guard navigationOverflow != overflow else {
            return
        }
        navigationOverflow = overflow
        updateLayout(size: frame.size, transition: transition)
    }
    
    func set(leftBar: BarView, centerView: BarView, rightView: BarView, controller: ViewController, animated: Bool) {
        
        let transition: ContainedViewLayoutTransition = .immediate
        navigationBarView.switchLeftView(leftBar, animation: animated ? .crossfade : .none)
        navigationBarView.switchCenterView(centerView, animation: animated ? .crossfade : .none)
        navigationBarView.switchRightView(rightView, animation: animated ? .crossfade : .none)
        
        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    fileprivate func updateScrollState(_ state: PeerInfoController<Context>.ScrollState, animated: Bool) {
        self.navBgView.change(opacity: state == .pageIn ? 1 : 0, animated: animated)
    }

    fileprivate func updateEdgeShadowOpacity(_ opacity: CGFloat) {
        let boosted = max(0, min(1, sqrt(opacity)))
        navigationBarView.setEdgeEffectOpacity(boosted, animated: false)
    }
}

public class PeerInfoController<Context: AccountContextProtocol>: EditableViewController<PeerInfoView<Context>, Context> {
    
    public enum Source {
        case none
        case reaction(MessageId)
    }
    
    private let updatedChannelParticipants:MetaDisposable = MetaDisposable()
    public let peerId:PeerId
    let peer: Peer
    
    private let arguments:Promise<PeerInfoArguments<Context>> = Promise()
    
    private let peerView:Atomic<PeerView?> = Atomic(value: nil)
    private var _groupArguments:GroupInfoArguments<Context>!
    private var _userArguments:UserInfoArguments<Context>!
    private var _channelArguments:ChannelInfoArguments<Context>!
    private var _topicArguments:TopicInfoArguments<Context>!

    private let peerInputActivitiesDisposable = MetaDisposable()
    
    private var argumentsAction: DisposableSet = DisposableSet()
    var disposable:MetaDisposable = MetaDisposable()

    private let mediaController: PeerMediaController<Context>
    
    private let revenueContext: StarsRevenueStatsContext?
    private let tonRevenueContext: StarsRevenueStatsContext?
    
    private let starGiftsProfile: ProfileGiftsContext
    private let savedMuicProfile: ProfileSavedMusicContext?

    public let threadInfo: ThreadInfo?
    
    let source: Source
    let stories: PeerExpiringStoryListContext?

    fileprivate enum ScrollState : Equatable {
        case pageUp
        case pageIn
    }
    
    private var scrollState: ScrollState = .pageUp
    
    private func updateScrollState(_ state: ScrollState, animated: Bool) {
        if state != self.scrollState {
            self.scrollState = state
            self.requestUpdateBackBar()
            self.requestUpdateCenterBar()
            self.requestUpdateRightBar()
            genericView.updateScrollState(state, animated: animated)
        }
    }
    
    public override func requestUpdateBackBar() {
        if let leftBarView = _leftBar as? BackNavigationBar {
            leftBarView.requestUpdate()
        }
        _leftBar?.style = barPresentation
    }
    
    public override func requestUpdateCenterBar() {
        if scrollState == .pageIn {
            setCenterTitle(defaultBarTitle)
        } else {
            setCenterTitle("")
        }
        setCenterStatus(defaultBarStatus)
        _centerBar.style = barPresentation
    }
    public override func requestUpdateRightBar() {
        _rightBar?.style = barPresentation
    }
    
    public override var defaultBarTitle: String {
        return localizedString("Telegram.PeerInfoController")
    }
    
    public override func setCenterTitle(_ text:String) {
        _centerBar.text = .initialize(string: text, color: barPresentation.textColor, font: .medium(.title))
    }
    public override func setCenterStatus(_ text: String?) {
        if let text = text {
            _centerBar.status = .initialize(string: text, color: barPresentation.grayTextColor, font: .normal(.text))
        } else {
            _centerBar.status = nil
        }
    }
    
    var nameColor:  PeerNameColor? {
        return PeerInfoHeadItem<Context>.nameColor(peer)
    }
    
    public override var barHeight: CGFloat {
        return 0
    }

    public override func updateNavigationHeaderOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        super.updateNavigationHeaderOverflow(overflow, transition: transition)
        if isLoaded() {
            genericView.updateNavigationOverflow(overflow, transition: transition)
        }
    }
    
    public override var barPresentation: ControlStyle {
        return .init(foregroundColor: theme.colors.text, backgroundColor: .clear, highlightColor: .clear, borderColor: .clear, grayTextColor: theme.colors.grayText, textColor: theme.colors.text)
    }
    
    public override func swapNavigationBar(leftView: BarView?, centerView: BarView?, rightView: BarView?, animation: NavigationBarSwapAnimation) {
        if leftView == leftBarView {
            self.genericView.set(leftBar: _leftBar, centerView: _centerBar, rightView: _rightBar, controller: self, animated: animation == .crossfade)
        } else {
            self.genericView.set(leftBar: _leftBar, centerView: centerView ?? _centerBar, rightView: rightView ?? _rightBar, controller: self, animated: animation == .crossfade)
        }
    }
    
    public static func push(navigation: NavigationViewController, context: Context, peerId: PeerId, threadInfo: ThreadInfo? = nil, stories: PeerExpiringStoryListContext? = nil, isAd: Bool = false, source: Source = .none, animated: Bool = true, mediaMode: PeerMediaCollectionMode? = nil, shake: Bool = true, starGiftsProfile: ProfileGiftsContext? = nil, albumId: Int32? = nil, initialState: ViewControllerState = .Normal) {


        guard !context.isFrozen else {
            PeerInfoUIHooks.shared.freezeAlert(context)
            return
        }

        if let controller = navigation.controller as? PeerInfoController, controller.peerId == peerId {
            if shake {
                controller.view.shake(beep: true)
            }
            if let mediaMode {
                controller.mediaController.setMode(mediaMode)
            }
            if initialState == .Edit {
                controller.state = .Edit
            }
            return
        }
        let signal = context.account.postbox.peerView(id:peerId) |> take(1) |> deliverOnMainQueue
        _ = (signal).start(next: { view in
            let mainPeer = peerViewMainPeer(view)
            let monoforumPeer = peerViewMonoforumMainPeer(view)

            var effectivePeer: Peer? = mainPeer

            if let mainPeer = mainPeer as? TelegramChannel, mainPeer.isMonoForum {
                if !mainPeer.groupAccess.canManageDirect {
                    effectivePeer = monoforumPeer
                }
            }


            if let peer = effectivePeer {
                if peer.restrictionText(context.contentSettings) == nil {
                    let controller = PeerInfoController(context: context, peer: peer, threadInfo: threadInfo, stories: stories, isAd: isAd, source: source, mediaMode: mediaMode, starGiftsProfile: starGiftsProfile, albumId: albumId, initialState: initialState)
                    navigation.push(controller, animated, style: animated ? .push : Optional.none)
                }
            }
        })
    }

    private let mediaMode: PeerMediaCollectionMode?
    private let albumId: Int32?
    private let initialState: ViewControllerState

    public init(context: Context, peer:Peer, threadInfo: ThreadInfo? = nil, stories: PeerExpiringStoryListContext? = nil, isAd: Bool = false, source: Source = .none, mediaMode: PeerMediaCollectionMode? = nil, starGiftsProfile: ProfileGiftsContext? = nil, albumId: Int32? = nil, linkedBotChannelId: PeerId? = nil, initialState: ViewControllerState = .Normal) {
        let peerId = peer.id
        self.peerId = peer.id
        self.albumId = albumId
        self.peer = peer
        self.source = source
        self.threadInfo = threadInfo
        self.mediaMode = mediaMode
        self.initialState = initialState
        self.starGiftsProfile = starGiftsProfile ?? ProfileGiftsContext(account: context.account, peerId: peerId)
        
        if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudChannel {
            self.stories = stories ?? .init(account: context.account, peerId: peerId)
        } else {
            self.stories = nil
        }
        
        var test: Bool = false
        #if DEBUG
        test = true
        #endif
        
        if peer.isBot, let botInfo = peer.botInfo, botInfo.flags.contains(.canEdit) || test {
            self.revenueContext = StarsRevenueStatsContext(account: context.account, peerId: peerId, ton: false)
            self.tonRevenueContext = StarsRevenueStatsContext(account: context.account, peerId: peerId, ton: true)
        } else if peer.isChannel || peer.isSupergroup {
            if peer.isAdmin {
                self.revenueContext = StarsRevenueStatsContext(account: context.account, peerId: peerId, ton: false)
                if peer.isChannel {
                    self.tonRevenueContext = StarsRevenueStatsContext(account: context.account, peerId: peerId, ton: true)
                } else {
                    self.tonRevenueContext = nil
                }
            } else {
                self.revenueContext = nil
                self.tonRevenueContext = nil
            }
        } else {
            self.revenueContext = nil
            self.tonRevenueContext = nil
        }
        
        if peer.isUser, !peer.isBot {
            self.savedMuicProfile = .init(account: context.account, peerId: peerId)
        } else {
            self.savedMuicProfile = nil
        }
        
        
        self.mediaController = PeerMediaController(context: context, peerId: linkedBotChannelId ?? peerId, threadInfo: threadInfo, isProfileIntended: true, isBot: peer.isBot, mode: mediaMode, starGiftsProfile: self.starGiftsProfile)
        super.init(context)
        
        bar = .init(height: 0, enableBorder: false)
        
        if threadInfo != nil {
        } else if initialState == .Edit {
        } else {
        }
        
        let pushViewController:(ViewController) -> Void = { [weak self] controller in
            self?.navigationController?.push(controller)
        }
        
        _groupArguments = GroupInfoArguments(context: context, peerId: peerId, state: GroupInfoState(), isAd: isAd, pushViewController: pushViewController, pullNavigation:{ [weak self] () -> NavigationViewController? in
            return self?.navigationController
        }, mediaController: { [weak self] in
            return self?.mediaController
        })
        
        _userArguments = UserInfoArguments(context: context, peerId: peerId, state: UserInfoState(), isAd: isAd, pushViewController: pushViewController, pullNavigation:{ [weak self] () -> NavigationViewController? in
             return self?.navigationController
        }, mediaController: { [weak self] in
             return self?.mediaController
        }, getStarsContext: { [weak self] in
            return self?.revenueContext
        }, getTonContext: { [weak self] in
            return self?.tonRevenueContext
        }, getStarGiftsContext: { [weak self] in
            return self?.starGiftsProfile
        }, getSavedMusicContext: { [weak self] in
            return self?.savedMuicProfile
        })
        _userArguments.getController = { [weak self] in self }


        _channelArguments = ChannelInfoArguments(context: context, peerId: peerId, state: ChannelInfoState(), isAd: isAd, pushViewController: pushViewController, pullNavigation:{ [weak self] () -> NavigationViewController? in
            return self?.navigationController
        }, mediaController: { [weak self] in
              return self?.mediaController
        }, getStarGiftsContext: { [weak self] in
            return self?.starGiftsProfile
        })
        if let threadInfo = threadInfo {
            _topicArguments = TopicInfoArguments(context: context, peerId: peerId, state: TopicInfoState(threadId: threadInfo.message.threadId), isAd: isAd, pushViewController: pushViewController, pullNavigation:{ [weak self] () -> NavigationViewController? in
                return self?.navigationController
            }, mediaController: { [weak self] in
                  return self?.mediaController
            })
        }
        
     
        
    }
    
    deinit {
        disposable.dispose()
        updatedChannelParticipants.dispose()
        peerInputActivitiesDisposable.dispose()
        argumentsAction.dispose()
        window?.removeAllHandlers(for: self)
    }
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        updateNavigationGlassTint()
    }
    
    private var isBirthdayPlayable = true
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let strongSelf = self {
                return strongSelf.returnKeyAction()
            }
            return .rejected
        }, with: self, for: .Return, priority: .high)
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let strongSelf = self {
                return strongSelf.returnKeyAction()
            }
            return .rejected
        }, with: self, for: .Return, priority: .high, modifierFlags: [.command])
     
        
        if isBirthdayPlayable {
            let birthday = self.peerView.with({ ($0?.cachedData as? CachedUserData)?.birthday })
            
            if let item = genericView.tableView.item(stableId: UserInfoEntry<Context>.birthday(sectionId: 0, text: "", false, viewType: .legacy).stableId.hashValue), let birthday, birthday.isToday {
                playBirthdayAnimations(item, birthday: birthday)
            }
            isBirthdayPlayable = false
        }
        
       
        
    }
    
    private func playBirthdayAnimations(_ item: TableRowItem, birthday: TelegramBirthday) {
        let context = self.context
        if let emoji = ["🎉", "🎆", "🎈"].randomElement() {
            
            let numbers:[Int: String] = [0: "0️⃣",
                          1: "1️⃣",
                          2: "2️⃣",
                          3: "3️⃣",
                          4: "4️⃣",
                          5: "5️⃣",
                          6: "6️⃣",
                          7: "7️⃣",
                          8: "8️⃣",
                          9: "9️⃣"]
            
            func separateNumbers(_ number: Int) -> [Int] {
                let numberString = String(number)
                var separatedNumbers = [Int]()
                
                for char in numberString {
                    if let digit = Int(String(char)) {
                        separatedNumbers.append(digit)
                    }
                }
                
                return separatedNumbers
            }

            
            let yearStickers: Signal<[TelegramMediaFile], NoError>
            if let year = birthday.yearsSince() {
                yearStickers = context.engine.stickers.loadedStickerPack(reference: .name("FestiveFontEmoji"), forceActualized: false) |> mapToSignal { loaded in
                    switch loaded {
                    case let .result(_, items, _):
                        var list: [TelegramMediaFile] = []
                        for number in separateNumbers(Int(year)) {
                            for item in items {
                                if item.file._parse().customEmojiText == numbers[number] {
                                    list.append(item.file._parse())
                                }
                            }
                        }
                        return .single(list)
                    default:
                        return .never()
                    }
                } |> take(1) |> deliverOnMainQueue
            } else {
                yearStickers = .single([])
            }
            
                
            _ = combineLatest(context.diceCache.animationEffect(for: emoji) |> take(1), yearStickers).startStandalone(next: { [weak item, weak self] values, yearStickers in
                if let file = values.first, let itemView = item?.view {
                    
                    let layer = InlineStickerView(account: context.account, file: file.2, size: NSMakeSize(300, 300), playPolicy: .onceEnd)
                    
                    layer.isEventLess = true
                    layer.userInteractionEnabled = false
                    
                    let point: NSPoint = itemView.convert(.zero, to: self?.genericView)

                    layer.setFrameOrigin(point.offsetBy(dx: 0, dy: -layer.frame.height / 2))
                    
                    self?.genericView.addSubview(layer)
                    
                    layer.animateLayer.triggerOnState = (.stoped, { [weak layer] state in
                        layer?.removeFromSuperview()
                    })
                    
                    layer.animateLayer.triggerOnState = (.finished, { [weak layer] state in
                        layer?.removeFromSuperview()
                    })
                    
                    for (i, number) in yearStickers.enumerated() {
                        
                        let layer = InlineStickerItemLayer(account: context.account, file: number, size: NSMakeSize(80, 80))
                        
                        layer.superview = self?.genericView
                        layer.isPlayable = true
                        
                        let point: NSPoint = itemView.convert(.zero, to: nil)

                        layer.frame = CGRect.init(origin: point.offsetBy(dx: CGFloat(i) * layer.size.width, dy: -layer.size.height / 2), size: layer.size)
                        
                        layer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                        layer.animateAlpha(from: 0, to: 1.0, duration: 0.2)

                        let windowSize = context.window.frame
                        
                        parabollicReactionAnimation(layer, fromPoint: layer.frame.origin, toPoint: NSMakePoint(windowSize.width / 2 + CGFloat(i) * layer.size.width, windowSize.height), window: context.window, completion: { _ in
                            
                        }, duration: 3.0)
                    }
                    
                    PlayConfetti(for: context.window)
                }
            })
        }
    }
    
    
    public override func viewWillDisappear(_ animated: Bool) {
        _userArguments?.setEmojiPermissionRequestsActive(false)
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        _userArguments?.setEmojiPermissionRequestsActive(true)
        super.viewWillAppear(animated)
        PeerInfoNavigationHooks.shared.prefetchQrStudio(context, peer)
        if initialState == .Edit {
            update(with: initialState)
        }
    }
    
    public override func getLeftBarViewOnce() -> BarView {
        return BarView(controller: self)
    }
    public override func getRightBarViewOnce() -> BarView {
        return BarView(controller: self)
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        if let currentEvent = NSApp.currentEvent, state == .Edit {
            if FastSettings.checkSendingAbility(for: currentEvent) {
                changeState()
                return .invoked
            }
        }
        
        return .invokeNext
    }
    
    private func updateNavigationGlassTint() {
        let genericView = self.genericView
        var header: (frame: NSRect, color: NSColor)?
        genericView.tableView.enumerateItems(with: { item in
            if let item = item as? PeerInfoHeadItem<Context> {
                if let color = item.navigationButtonColor, let view = item.headerContainerView {
                    header = (genericView.convert(view.bounds, from: view), color)
                }
                return false
            }
            return true
        })
        let back = (_leftBar as? BackNavigationBar)?.button
        let visibleButtons = ([back].compactMap { $0 } + stackedBar.buttons).filter { !$0.isHidden }
        let tint: NSColor? = header.flatMap { header in
            let overHeader = visibleButtons.contains(where: { button in
                let frame = genericView.convert(button.bounds, from: button)
                return frame.midX > header.frame.minX && frame.midX < header.frame.maxX && frame.maxY < header.frame.maxY
            })
            return overHeader ? header.color : nil
        }
        if tint == navigationGlassTint {
            return
        }
        navigationGlassTint = tint
        back?.glassTintColor = tint
        for button in stackedBar.buttons {
            button.glassTintColor = tint
            (button.additionalGlassEffectView as? LiquidGlassView)?.customTint = tint
        }
    }
    
    private var navigationGlassTint: NSColor?
    private var _leftBar: BarView!
    private var _centerBar: TitledBarView!
    private var _rightBar: BarView!

    public override func viewDidLoad() -> Void {


        _leftBar = super.getLeftBarViewOnce()
        _centerBar = super.getCenterBarViewOnce()
        _rightBar = super.getRightBarViewOnce()

        _centerBar.userInteractionEnabled = false
        _centerBar.isEventLess = true
        
        genericView.set(leftBar: _leftBar, centerView: _centerBar, rightView: _rightBar , controller: self, animated: false)

        super.viewDidLoad()
        
        genericView.updateScrollState(nameColor != nil ? scrollState : .pageIn, animated: false)
        if nameColor != nil {
            genericView.updateEdgeShadowOpacity(0)
        }
        

        genericView.layer?.masksToBounds = false
        
        genericView.tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] _ in
            self?.updateNavigationGlassTint()
        }))
        
        self.genericView.tableView.hasVerticalScroller = false
        self.genericView.tableView.verticalScrollElasticity = .none
        
        self.genericView.tableView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        if peer.isChannel {
            _ = context.engine.peers.requestRecommendedChannels(peerId: peerId, forceUpdate: true).startStandalone()
        } else if peer.isBot {
            _ = context.engine.peers.requestRecommendedBots(peerId: peerId, forceUpdate: true).startStandalone()
        }
        
        
        let previousEntries = Atomic<[AppearanceWrapperEntry<PeerInfoSortableEntry>]?>(value: nil)
        let context = self.context
        let peerId = self.peerId
        let initialSize = atomicSize
        let onMainQueue: Atomic<Bool> = Atomic(value: true)
        let threadId = threadInfo?.message.threadId
                        
        mediaController.navigationController = self.navigationController
        mediaController._frameRect = NSMakeRect(0, 0, bounds.width, bounds.height)
        mediaController.bar = .init(height: 0)
        
        mediaController.loadViewIfNeeded()
        
        let inputActivity = context.account.peerInputActivities(peerId: .init(peerId: peerId, category: .global))
            |> map { activities -> [PeerId : PeerInputActivity] in
                return activities.reduce(into: [:], { current, activity in
                    current[activity.0] = activity.1
                })
        }
        |> distinctUntilChanged
        
        let inputActivityState: Promise<[PeerId : PeerInputActivity]> = Promise([:])
        

        arguments.set(context.account.postbox.loadedPeerWithId(peerId) |> deliverOnMainQueue |> mapToSignal { [weak self] peer in
            guard let `self` = self else {return .never()}
            
            self._topicArguments?.peer = peer
            self._groupArguments?.peer = peer
            self._channelArguments?.peer = peer
            self._userArguments?.peer = peer

            if peer.isForumOrMonoForum && threadId != nil {
                return .single(self._topicArguments)
            }
            if peer.isGroup || peer.isSupergroup {
                inputActivityState.set(inputActivity)
            }
            
            if peer.isGroup || peer.isSupergroup {
                return .single(self._groupArguments)
            } else if peer.isChannel {
                return .single(self._channelArguments)
            } else {
                return .single(self._userArguments)
            }
        })
        
        let actionsDisposable = DisposableSet()
        
        var loadMoreControl: PeerChannelMemberCategoryControl?
        
        
        
        let mediaTabsData: Signal<PeerMediaTabsData, NoError> = mediaController.tabsValue
        let mediaReady = mediaController.ready.get() |> take(1)
        
        
        let source = self.source
        
        let storiesSignal: Signal<PeerExpiringStoryListContext.State?, NoError>
        if let stories = self.stories {
            storiesSignal = stories.state |> map(Optional.init)
        } else {
            storiesSignal = .single(nil)
        }
        
        let revenueState: Signal<StarsRevenueStatsContextState?, NoError>
        if let revenueContext {
            revenueState = revenueContext.state |> map(Optional.init)
        } else {
            revenueState = .single(nil)
        }
        
        let tonRevenueState: Signal<StarsRevenueStatsContextState?, NoError>
        if let tonRevenueContext {
            tonRevenueState = tonRevenueContext.state |> map(Optional.init)
        } else {
            tonRevenueState = .single(nil)
        }
        
        let savedMuicProfileState: Signal<ProfileSavedMusicContext.State?, NoError>
        if let savedMuicProfile {
            savedMuicProfileState = savedMuicProfile.state |> map(Optional.init)
        } else {
            savedMuicProfileState = .single(nil)
        }
        
        let personalChannelSignal: Signal<UserInfoPersonalChannel?, NoError>
        if peerId.namespace == Namespaces.Peer.CloudUser {
            personalChannelSignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.PersonalChannel(id: peerId)) |> mapToSignal { value in
                switch value {
                case let .known(channel):
                    if let channel = channel {
                        let message = context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: channel.peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 10, fixedCombinedReadStates: nil) |> map {
                            $0.0.entries.last?.message
                        }
                        return combineLatest(context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: channel.peerId)), message) |> map { peer, message in
                            if let peer {
                                return UserInfoPersonalChannel(peer: peer, message: message.flatMap(EngineMessage.init), subscribers: channel.subscriberCount)
                            } else {
                                return nil
                            }
                        }
                    } else {
                        return .single(nil)
                    }
                case .unknown:
                    return .single(nil)
                }
            }
        } else {
            personalChannelSignal = .single(nil)
        }
        
        let transition: Signal<(PeerView, TableUpdateTransition, MessageHistoryThreadData?, EnginePeer?), NoError> = arguments.get() |> mapToSignal { arguments in
            
            let inviteLinksCount: Signal<Int32, NoError>
            if let peer = arguments.peer as? TelegramChannel, peer.groupAccess.canCreateInviteLink {
                if let arguments = arguments as? GroupInfoArguments<Context> {
                    inviteLinksCount = arguments.linksManager.state |> map {
                        $0.effectiveCount
                    }
                } else if let arguments = arguments as? ChannelInfoArguments<Context> {
                    inviteLinksCount = arguments.linksManager.state |> map {
                        $0.effectiveCount
                    }
                } else {
                    inviteLinksCount = .single(0)
                }
            } else {
                inviteLinksCount = .single(0)
            }
            
            
            let channelMembersPromise = Promise<[RenderedChannelParticipant]>()
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                if let peer = arguments.peer as? TelegramChannel, peer.isSupergroup || peer.isGigagroup {
                    let (disposable, control) = context.peerChannelMemberCategoriesContextsManager.recent(peerId: peerId, updated: { state in
                        channelMembersPromise.set(.single(state.list))
                    })
                    actionsDisposable.add(disposable)

                    let (contactsDisposable, _) = context.peerChannelMemberCategoriesContextsManager.contacts(peerId: peerId, updated: { _ in
                        
                    })
                    actionsDisposable.add(contactsDisposable)
                    
                    loadMoreControl = control
                } else {
                    channelMembersPromise.set(.single([]))
                }
            } else {
                channelMembersPromise.set(.single([]))
            }
            
            let joinRequestsCount: Signal<Int32, NoError>
            if let peer = arguments.peer as? TelegramChannel, peer.groupAccess.canCreateInviteLink {
                if let arguments = arguments as? GroupInfoArguments<Context> {
                    joinRequestsCount = arguments.requestManager.state |> map {
                        Int32($0.waitingCount)
                    }
                } else if let arguments = arguments as? ChannelInfoArguments<Context> {
                    joinRequestsCount = arguments.requestManager.state |> map {
                        Int32($0.waitingCount)
                    }
                } else {
                    joinRequestsCount = .single(0)
                }
            } else {
                joinRequestsCount = .single(0)
            }
            
            
            let availableReactions: Signal<AvailableReactions?, NoError> = context.reactions.stateValue
            
            
            let threadData: Signal<MessageHistoryThreadData?, NoError>
            let threadPeer: Signal<EnginePeer?, NoError>
            if let threadId = threadId {
                let key: PostboxViewKey = .messageHistoryThreadInfo(peerId: peerId, threadId: threadId)
                threadData = context.account.postbox.combinedView(keys: [key]) |> map { views in
                    let view = views.views[key] as? MessageHistoryThreadInfoView
                    let data = view?.info?.data.get(MessageHistoryThreadData.self)
                    return data
                }
                threadPeer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(threadId)))
            } else {
                threadData = .single(nil)
                threadPeer = .single(nil)
            }
            
            
            
            return combineLatest(queue: prepareQueue, context.account.viewTracker.peerView(peerId, updateData: true), arguments.statePromise, appearanceSignal, inputActivityState.get(), channelMembersPromise.get(), mediaTabsData, mediaReady, inviteLinksCount, joinRequestsCount, availableReactions, threadData, threadPeer, storiesSignal, personalChannelSignal, revenueState, tonRevenueState, webAppPermissionsState(context: context, peerId: peerId), savedMuicProfileState)
            |> mapToQueue { view, state, appearance, inputActivities, channelMembers, mediaTabsData, _, inviteLinksCount, joinRequestsCount, availableReactions, threadData, threadPeer, stories, personalChannel, revenueState, tonRevenueState, webAppPermissionsState, savedMuicProfileState -> Signal<(PeerView, TableUpdateTransition, MessageHistoryThreadData?, EnginePeer?), NoError> in
                    
                    
                let entries:[AppearanceWrapperEntry<PeerInfoSortableEntry>] = peerInfoEntries(view: view, threadData: threadData, threadPeer: threadPeer, arguments: arguments, inputActivities: inputActivities, channelMembers: channelMembers, mediaTabsData: mediaTabsData, inviteLinksCount: inviteLinksCount, joinRequestsCount: joinRequestsCount, availableReactions: availableReactions, source: source, stories: stories, personalChannel: personalChannel, revenueState: revenueState, tonRevenueState: tonRevenueState, webAppPermissionsState: webAppPermissionsState, savedMuicProfileState: savedMuicProfileState).map({PeerInfoSortableEntry(entry: $0)}).map({AppearanceWrapperEntry(entry: $0, appearance: appearance)})
                    let previous = previousEntries.swap(entries)
                    return prepareEntries(from: previous, to: entries, account: context.account, initialSize: initialSize.modify({$0}), peerId: peerId, arguments:arguments, animated: previous != nil) |> runOn(onMainQueue.swap(false) ? .mainQueue() : prepareQueue) |> map { (view, $0, threadData, threadPeer) }
                    
            } |> deliverOnMainQueue
            } |> afterDisposed {
                actionsDisposable.dispose()
            }
                
        
        var scrollToMedia = false
        
        disposable.set(transition.start(next: { [weak self] (peerView, transition, threadData, threadPeer) in
            
            _ = self?.peerView.swap(peerView)
            
            let editable:Bool
            if let peer = peerViewMainPeer(peerView) {
                if let peer = peer as? TelegramChannel {
                    switch peer.info {
                    case .broadcast:
                        editable = peer.adminRights != nil || peer.flags.contains(.isCreator)
                    case .group:
                        if let threadData = threadData {
                            let right = peer.adminRights?.rights.contains(.canManageTopics) ?? false
                            editable = ((peer.isAdmin && right) || threadData.isOwnedByMe) && threadPeer == nil
                        } else {
                            editable = peer.adminRights != nil || peer.flags.contains(.isCreator)
                        }
                    }
                } else if let group = peer as? TelegramGroup {
                    switch group.role {
                    case .admin, .creator:
                        editable = true
                    default:
                        editable = group.groupAccess.canEditGroupInfo || group.groupAccess.canEditMembers
                    }
                } else if peer is TelegramUser, !peer.isBot, peerView.peerIsContact {
                    if peerId.namespace == Namespaces.Peer.SecretChat {
                        editable = false
                    } else {
                        editable = true
                    }
                } else if let botInfo = peer.botInfo, botInfo.flags.contains(.canEdit) {
                    editable = true
                } else {
                    editable = context.peerId == peerId
                }
            } else {
                editable = false
            }
            self?.set(editable: editable)
            
            self?.genericView.tableView.merge(with:transition)
            self?.updateNavigationGlassTint()
            self?.readyOnce()
            
            if let peer = peerViewMainPeer(peerView) {
                if let channel = peer as? TelegramChannel {
                    switch channel.participationStatus {
                    case .member, .left:
                        break
                    case .kicked:
                        self?.navigationController?.close()
                    }
                } else if let group = peer as? TelegramGroup {
                    switch group.membership {
                    case .Member, .Left:
                        break
                    case .Removed:
                        self?.navigationController?.close()
                    }
                }
            }
            
            if let mediaMode = self?.mediaMode, !scrollToMedia {
                var stableId: AnyHashable?
                self?.genericView.tableView.enumerateItems(with: { item in
                    if let item = item as? PeerMediaBlockRowItem<Context> {
                        stableId = item.stableId
                        return false
                    } else {
                        return true
                    }
                })
                
                if let stableId {
                    scrollToMedia = true
                    self?.genericView.tableView.scroll(to: .top(id: stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: 0))
                    if let albumId = self?.albumId {
                        switch mediaMode {
                        case .stories:
                            self?.mediaController.selectStoryAlbum(albumId)
                        case .gifts:
                            self?.mediaController.selectGiftsAlbum(albumId)
                        default:
                            break
                        }
                    }
                }
            }

        }))
        
     
        genericView.tableView.setScrollHandler { position in
            if let loadMoreControl = loadMoreControl {
                switch position.direction {
                case .bottom:
                    context.peerChannelMemberCategoriesContextsManager.loadMore(peerId: peerId, control: loadMoreControl)
                default:
                    break
                }
            }
        }
       
        
    }
    
    public override func backKeyAction() -> KeyHandlerResult {
        if state == .Edit {
            return .invokeNext
        }
        return .rejected
    }
    
    func updateArguments(_ f:@escaping(PeerInfoArguments<Context>) -> Void) {
        argumentsAction.add((arguments.get() |> take(1)).start(next: { arguments in
            f(arguments)
        }))
    }
    
    public override func update(with state: ViewControllerState) {
        
        if let peerView = peerView.with ({$0}) {
            updateArguments({ [weak self] arguments in
                guard let `self` = self else {
                    return
                }
                if self.peerId == self.context.peerId {
                    PeerInfoNavigationHooks.shared.editAccountInfo(arguments.context, { [weak self] controller in
                        self?.navigationController?.push(controller)
                    })
                } else {
                    let updateState = arguments.updateEditable(state == .Edit, peerView: peerView, controller: self)
                    self.genericView.tableView.scroll(to: .up(true))
                    
                    if updateState {
                        self.applyState(state)
                    }
                }
            })
        }
    }
    
    private func applyState(_ state: ViewControllerState) {
        super.update(with: state)
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        if state == .Edit {
            updateArguments({ arguments in
                arguments.dismissEdition()
            })
            state = .Normal
            return .invoked
        }
        return .rejected
    }
    
}

