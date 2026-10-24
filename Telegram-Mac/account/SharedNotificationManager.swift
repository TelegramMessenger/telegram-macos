import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import BuildConfig
import TGUIKit
import ObjcUtils
import InAppSettings
import PasscodeCore
import WalletContext

func getNotificationMessageId(userInfo:[AnyHashable: Any], for prefix: String) -> MessageId? {
    if let msgId = userInfo["\(prefix).message.id"] as? Int32, let msgNamespace = userInfo["\(prefix).message.namespace"] as? Int32, let namespace = userInfo["\(prefix).peer.namespace"] as? Int32, let id = userInfo["\(prefix).peer.id"] as? Int64 {
        return MessageId(peerId: PeerId(namespace: PeerId.Namespace._internalFromInt32Value(namespace), id: PeerId.Id._internalFromInt64Value(id)), namespace: msgNamespace, id: msgId)
    }
    return nil
}

func getNotificationToneFile(account: Account, sound: PeerMessageSound) -> Signal<String?, NoError> {
    let engine = TelegramEngine(account: account)
    return engine.peers.notificationSoundList() |> take(1) |> mapToSignal { list in
        return fileNameForNotificationSound(postbox: account.postbox, sound: sound, defaultSound: nil, list: list?.sounds) |> map { resource in
            if let resource = resource {
                return resourcePath(account.postbox, resource)
            } else {
                return "default"
            }
        }
    }
}

struct NotificationPresentation {
    let muted: Bool
    let sound: PeerMessageSound
    let showPreview: Bool
    let hideSender: Bool
}

private func effectiveCategorySound(_ sound: PeerMessageSound) -> PeerMessageSound {
    if sound == defaultCloudPeerNotificationSound {
        return .default
    }
    return sound
}

private func notificationPresentation(source: SharedNotificationManager.Source, message: Message, globalSettings: GlobalNotificationSettingsSet, peerSettings: TelegramPeerNotificationSettings?) -> NotificationPresentation {
    switch source {
    case .reaction:
        let reactionSettings = globalSettings.reactionSettings
        return NotificationPresentation(muted: false, sound: effectiveCategorySound(reactionSettings.sound), showPreview: true, hideSender: reactionSettings.hideSender == .hide)
    case .messages:
        let categorySettings: MessageNotificationSettings
        switch message.peers[message.id.peerId] {
        case let channel as TelegramChannel:
            if case .broadcast = channel.info {
                categorySettings = globalSettings.channels
            } else {
                categorySettings = globalSettings.groupChats
            }
        case is TelegramUser, is TelegramSecretChat:
            categorySettings = globalSettings.privateChats
        default:
            categorySettings = globalSettings.groupChats
        }
        let sound: PeerMessageSound
        if let peerSound = peerSettings?.messageSound, peerSound != .default {
            sound = peerSound
        } else {
            sound = effectiveCategorySound(categorySettings.sound)
        }
        let showPreview: Bool
        switch peerSettings?.displayPreviews ?? .default {
        case .show:
            showPreview = true
        case .hide:
            showPreview = false
        case .default:
            showPreview = categorySettings.displayPreviews
        }
        return NotificationPresentation(muted: peerSettings?.isMuted ?? false, sound: sound, showPreview: showPreview, hideSender: false)
    }
}

struct LockNotificationsData : Equatable {
    let screenLock:Bool
    let passcodeLock:Bool
    
    init() {
        self.screenLock = false
        self.passcodeLock = false
    }
    
    init(screenLock: Bool, passcodeLock: Bool) {
        self.screenLock = screenLock
        self.passcodeLock = passcodeLock
    }
    
    func withUpdatedScreenLock(_ lock: Bool) -> LockNotificationsData {
        return LockNotificationsData(screenLock: lock, passcodeLock: passcodeLock)
    }
    func withUpdatedPasscodeLock(_ lock: Bool) -> LockNotificationsData {
        return LockNotificationsData(screenLock: screenLock, passcodeLock: lock)
    }
    
    static func ==(lhs:LockNotificationsData, rhs: LockNotificationsData) -> Bool {
        return lhs.screenLock == rhs.screenLock && lhs.passcodeLock == rhs.screenLock
    }
    
    var isLocked: Bool {
        return screenLock || passcodeLock
    }
}

final class SharedNotificationBindings {
    let navigateToChat:(Account, PeerId) -> Void
    let navigateToThread:(Account, MessageId, MessageId?, MessageHistoryThreadData?) -> Void // threadId, fromId
    let navigateToStory:(Account, PeerId) -> Void
    let updateCurrectController:()->Void
    let applyMaxReadIndexInteractively:(MessageIndex)->Void
    init(navigateToChat: @escaping(Account, PeerId) -> Void, navigateToThread: @escaping(Account, MessageId, MessageId?, MessageHistoryThreadData?) -> Void, navigateToStory: @escaping(Account, PeerId) -> Void, updateCurrectController: @escaping()->Void, applyMaxReadIndexInteractively:@escaping(MessageIndex)->Void) {
        self.navigateToChat = navigateToChat
        self.navigateToThread = navigateToThread
        self.navigateToStory = navigateToStory
        self.updateCurrectController = updateCurrectController
        self.applyMaxReadIndexInteractively = applyMaxReadIndexInteractively
    }
}


final class SharedNotificationManager : NSObject, NSUserNotificationCenterDelegate {

    private let screenLocked:Promise<LockNotificationsData> = Promise(LockNotificationsData())
    private(set) var _lockedValue:LockNotificationsData = LockNotificationsData() {
        didSet {
            didUpdateLocked?(_lockedValue)
        }
    }
    
    var didUpdateLocked:((LockNotificationsData)->Void)? = nil
    
    private let _passlock = Promise<Bool>()

    var passlocked: Signal<Bool, NoError> {
        return _passlock.get()
    }

    
    private func updateLocked(_ f:(LockNotificationsData) -> LockNotificationsData) {
        _lockedValue = f(_lockedValue)
        if #available(macOS 10.15, *) {
            PasscodeSession.setApplicationAvailable(!_lockedValue.passcodeLock)
        }
        screenLocked.set(.single(_lockedValue))
    }

    var isPasscodeLocked: Signal<Bool, NoError> {
        return screenLocked.get() |> map { $0.passcodeLock } |> distinctUntilChanged
    }
    
    private let disposableDict: DisposableDict<AccountRecordId> = DisposableDict()
    private let storyDisposableDict: DisposableDict<AccountRecordId> = DisposableDict()
    private let inAppSettingsDisposable = MetaDisposable()
    private let lockTimeoutDisposable = MetaDisposable()
    let accountManager: AccountManager<TelegramAccountManagerTypes>
    var resignTimestamp:Int32? = nil
    
    var activeAccounts: (primary: Account?, accounts: [(AccountRecordId, Account)]) = (primary: nil, accounts: [])
    let bindings: SharedNotificationBindings
    private let appEncryption: AppEncryptionParameters
    
    private var lockers:[PasscodeLockController] = []
    
    init(activeAccounts: Signal<(primary: Account?, accounts: [(AccountRecordId, Account)]), NoError>, appEncryption: AppEncryptionParameters, accountManager: AccountManager<TelegramAccountManagerTypes>, bindings: SharedNotificationBindings) {
        self.accountManager = accountManager
        self.bindings = bindings
        self.appEncryption = appEncryption
        
        
        super.init()

        if #available(macOS 10.15, *) {
            PasscodeSession.setApplicationAvailable(true)
        }
        
        UNUserNotifications.initialize(manager: self)
        
        inAppSettingsDisposable.set((appNotificationSettings(accountManager: accountManager) |> deliverOnMainQueue).start(next: { [weak self] inAppSettings in
            self?.showNotificationsOutOfFocus = inAppSettings.showNotificationsOutOfFocus
            self?.requestUserAttention = inAppSettings.requestUserAttention
        }))

        UNUserNotifications.current?.authorize(completion: { value in
            
        })
        
//        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
//        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window)
        
        
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenIsLocked), name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenIsUnlocked), name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        
        _ = (_passlock.get() |> mapToSignal { show in additionalSettings(accountManager: accountManager) |> take(1) |> map { (show, $0) }} |> deliverOnMainQueue |> mapToSignal { show, settings -> Signal<Bool, NoError> in
            if show {
                closeInstantView()
                closeGalleryViewer(false)
                closePipVideo()
                
                var signals:[Signal<Bool, NoError>] = []
                
                
                let lock: (AccountContext)->Void = { context in
                    closeAllModals(window: context.window)
                    _ = context.sharedContext.getAudioPlayer()?.pause()
                    let controller = PasscodeLockController(accountManager, useTouchId: settings.useTouchId, logoutImpl: {
                        return self.logout()
                    }, updateCurrectController: bindings.updateCurrectController)
                    
                    self.lockers.append(controller)
                    showModal(with: controller, for: context.window, isOverlay: true)
                    signals.append(controller.doneValue)
                }
                appDelegate?.enumerateExternalChatContexts(lock)
                appDelegate?.enumerateAccountContexts(lock)
                let signal: Signal<Bool, NoError> = combineLatest(signals)
                |> map { values in
                    if values.contains(true) {
                        return false
                    } else {
                        return true
                    }
                }
                return .single(show) |> then(signal)
            }
            return .never()
        } |> deliverOnMainQueue).start(next: { lock in
                
                appDelegate?.enumerateAccountContexts({ context in
                    for subview in context.window.contentView!.subviews {
                        if let subview = subview as? SplitView {
                            subview.isHidden = lock
                            break
                        }
                    }
                })
                if !lock {
                    while !self.lockers.isEmpty {
                        self.lockers.removeLast().close()
                    }
                }
                
                self.updateLocked { previous -> LockNotificationsData in
                    return previous.withUpdatedPasscodeLock(lock)
                }
            })
        
        _ = (activeAccounts |> deliverOnMainQueue).start(next: { accounts in
            let activeIds = Set(accounts.accounts.map { $0.0 })
            for (id, _) in self.activeAccounts.accounts where !activeIds.contains(id) {
                self.disposableDict.set(nil, forKey: id)
                self.storyDisposableDict.set(nil, forKey: id)
            }
            for account in accounts.accounts {
                self.startNotifyListener(with: account.1, primary: account.0 == accounts.primary?.id)
            }
            self.activeAccounts = accounts
        })
        
        
        let cachedLockTimeout = Atomic<Int32??>(value: nil)
        lockTimeoutDisposable.set(combineLatest(accountManager.accessChallengeData(), passcodeSettingsView(accountManager)).start(next: { challenge, settings in
            let _ = cachedLockTimeout.swap(.some(challenge.data.isLockable ? settings.timeout : nil))
        }))
        
        let passlock = Signal<Void, NoError>.single(Void()) |> delay(10, queue: Queue.concurrentDefaultQueue()) |> restart |> mapToSignal { () -> Signal<Int32?, NoError> in
            if let timeout = cachedLockTimeout.with({ $0 }) {
                return .single(timeout)
            }
            return accountManager.transaction { transaction -> Int32? in
                if transaction.getAccessChallengeData().isLockable {
                    return passcodeSettings(transaction).timeout
                } else {
                    return nil
                }
            }
            } |> map { [weak self] timeout -> Bool in
                if let timeout = timeout {
                    if let resignTimestamp = self?.resignTimestamp  {
                        let current = Int32(Date().timeIntervalSince1970)
                        if current - resignTimestamp > timeout {
                            return true
                        }
                    }
                    return Int64(timeout) < SystemIdleTime()
                } else  {
                    return false
                }
            }
            |> filter { _ in
                return !self._lockedValue.passcodeLock
            }
            |> deliverOnMainQueue
        

        _passlock.set(passlock)
        
    }
    
    func updatePasslock(_ signal: Signal<Bool, NoError>) {
        guard !_lockedValue.passcodeLock else {
            return
        }
        _passlock.set(signal)
    }
    
    func find(_ id: AccountRecordId?) -> AccountContext? {
        return appDelegate?.activeContext(for: id)
    }
    
    func logout() -> Signal<Never, NoError> {
        let accountManager = self.accountManager
        let signal = combineLatest(self.activeAccounts.accounts.map { logoutFromAccount(id: $0.0, accountManager: self.accountManager, alreadyLoggedOutRemotely: false) }) |> deliverOnMainQueue
        appEncryption.remove()
        if #available(macOS 10.15, *) {
            _ = try? resetWalletLocalSecrets()
        }
        let removePasscode = accountManager.transaction { $0.setAccessChallengeData(.none) }  |> deliverOnMainQueue
        return combineLatest(removePasscode, signal) |> ignoreValues
    }
    
    
    @objc public func windowDidBecomeKey() {
        self.resignTimestamp = nil
    }
    
    @objc public func windowDidResignKey() {
        self.resignTimestamp = Int32(Date().timeIntervalSince1970)
    }
    
    @objc func screenIsLocked() {
        
        if !_lockedValue.passcodeLock {
            _passlock.set(accountManager.transaction { transaction -> Bool in
                switch transaction.getAccessChallengeData() {
                case .none:
                    return false
                default:
                    return true
                }
            })
        }
        
        updateLocked { (previous) -> LockNotificationsData in
            return previous.withUpdatedScreenLock(true)
        }
        _isLockedValue.set(true)
    }
    
    @objc func screenIsUnlocked() {
        updateLocked { (previous) -> LockNotificationsData in
            return previous.withUpdatedScreenLock(false)
        }
        _isLockedValue.set(false)
    }
    
    private let _isLockedValue = ValuePromise(false, ignoreRepeated: true)
    var isLockedValue: Signal<Bool, NoError> {
        return _isLockedValue.get()
    }

    
    var isLocked: Bool {
        return _lockedValue.isLocked
    }
    
    private(set) var showNotificationsOutOfFocus: Bool = true
    private(set) var requestUserAttention: Bool = false
    
    enum Source {
        case messages([Message], PeerGroupId, MessageHistoryThreadData?)
        case reaction(Message, Peer, MessageReaction.Reaction, Int32, TelegramMediaFile?, MessageHistoryThreadData?)
        
        var messages:[Message] {
            switch self {
            case let .messages(messages, _, _):
                return messages
            case let .reaction(message, _, _, _, _, _):
                return [message]
            }
        }
        
        var threadData: MessageHistoryThreadData? {
            switch self {
            case let .messages(_, _, threadData):
                return threadData
            case let .reaction(_, _, _, _, _, threadData):
                return threadData
            }
        }
        
        var groupId: PeerGroupId? {
            switch self {
            case let .messages(_, groupId, _):
                return groupId
            case .reaction:
                return nil
            }
        }
        func key(for message: Message) -> String {
            switch self {
            case let .reaction(_, peer, value, timestamp, _, _):
                return "reaction_\(message.id.string)_\(peer.id.toInt64())_\(value)_\(timestamp)"
            case .messages:
                return "message_\(message.id.string)"
            }
        }
    }
    
    func startNotifyListener(with account: Account, primary: Bool) {
        let screenLocked = self.screenLocked
        var alreadyNotified:Set<String> = Set()
        var alreadyNotifiedOrder:[String] = []
        
        let engine = TelegramEngine(account: account)
        
        struct ReactionTuple {
            var reactionAuthor: Peer
            var reaction: MessageReaction.Reaction
            var message: Message
            var timestamp: Int32
            var file: TelegramMediaFile?
            var threadData: MessageHistoryThreadData?
        }
        
        let reactions: Signal<[ReactionTuple], NoError> = .single([]) |> then(account.stateManager.reactionNotifications |> filter { !$0.isEmpty } |> mapToSignal { reactions in
            
            
            var fileIds: Set<Int64> = Set()
            for reaction in reactions {
                switch reaction.reaction {
                case let .custom(fileId):
                    fileIds.insert(fileId)
                default:
                    break
                }
            }
            
            return engine.stickers.resolveInlineStickers(fileIds: Array(fileIds)) |> mapToSignal { files in
                return engine.account.postbox.transaction { transaction in
                    let reactionSettings = transaction.getPreferencesEntry(key: PreferencesKeys.globalNotifications)?.get(GlobalNotificationSettings.self)?.effective.reactionSettings ?? PeerReactionNotificationSettings.default
                    
                    var reactions:[ReactionTuple] = reactions.map { .init(reactionAuthor: $0, reaction: $1, message: $2, timestamp: $3) }.filter { reaction in
                        switch reactionSettings.messages {
                        case .nobody:
                            return false
                        case .contacts:
                            if !transaction.isPeerContact(peerId: reaction.reactionAuthor.id) {
                                return false
                            }
                        case .everyone:
                            break
                        }
                        if let notifications = transaction.getPeerNotificationSettings(id: reaction.message.id.peerId) as? TelegramPeerNotificationSettings, notifications.isMuted {
                            return false
                        }
                        return true
                    }
                    
                    for (i, reaction) in reactions.enumerated() {
                        var threadData: MessageHistoryThreadData?
                        let message = reaction.message
                        for attr in message.attributes {
                            if let attribute = attr as? ReplyMessageAttribute {
                                if let threadId = attribute.threadMessageId {
                                    threadData = transaction.getMessageHistoryThreadInfo(peerId: message.id.peerId, threadId: Int64(threadId.id))?.data.get(MessageHistoryThreadData.self)
                                }
                            }
                        }
                        reactions[i].threadData = threadData
                    }
                    
                    for (i, reaction) in reactions.enumerated() {
                        sw: switch reaction.reaction {
                            case let .custom(fileId):
                                reactions[i].file = files[fileId]
                            default:
                                break sw
                        }
                    }
                    return reactions
                }
                
            }
        })
        
        let notificationMessages: Signal<[([Message], PeerGroupId, Bool, MessageHistoryThreadData?)], NoError> = .single([]) |> then(account.stateManager.notificationMessages |> filter { !$0.isEmpty })
        
        disposableDict.set((combineLatest(notificationMessages, reactions) |> mapToSignal { messages, reactions -> Signal<([Source], InAppNotificationSettings), NoError> in
            return appNotificationSettings(accountManager: self.accountManager) |> take(1) |> mapToSignal { inAppSettings -> Signal<([Source], InAppNotificationSettings), NoError> in
                if inAppSettings.enabled && inAppSettings.muteUntil < Int32(Date().timeIntervalSince1970) {
                    
                    let msgs:[Source] = messages.filter
                    {
                        $0.2 || ($0.0.isEmpty || $0.0[0].wasScheduled)
                    }.map {
                        return .messages($0.0, $0.1, $0.3)
                    }
                    let rctns:[Source] = reactions.map {
                        .reaction($0.message, $0.reactionAuthor, $0.reaction, $0.timestamp, $0.file, $0.threadData)
                    }

                    return .single((msgs + rctns, inAppSettings))
                } else {
                    return .complete()
                }
                
            }
        }
        |> mapToSignal { sources, inAppSettings -> Signal<([Source],[MessageId:NSImage], InAppNotificationSettings), NoError> in
                
                var photos:[Signal<(MessageId, CGImage?),NoError>] = []
            
                for source in sources {
                    for message in source.messages {
                        var peer = message.author
                        if let mainPeer = coreMessageMainPeer(message) {
                            if mainPeer is TelegramChannel || mainPeer is TelegramGroup || message.wasScheduled {
                                peer = mainPeer
                            }
                        }
                        if message.id.peerId == repliesPeerId {
                            peer = message.chatPeer(account.peerId)
                        }
                        if let peer = peer {
                            if let threadData = source.threadData {
                                photos.append(peerAvatarImage(account: account, photo: .topic(threadData.info, message.threadId == 1), genCap: false) |> map { data in return (message.id, data.0)})
                            } else {
                                photos.append(peerAvatarImage(account: account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, peer.displayLetters, message, nil), genCap: false) |> map { data in return (message.id, data.0)})
                            }
                        }
                    }
                }
                return  combineLatest(photos) |> take(1) |> map { resources in
                    var images:[MessageId:NSImage] = [:]
                    for (messageId,image) in resources {
                        if let image = image {
                            images[messageId] = NSImage(cgImage: image, size: NSMakeSize(50,50))
                        }
                    }
                    return (sources, images, inAppSettings)
                }
            } |> mapToSignal { sources, images, inAppSettings -> Signal<([Source], [MessageId:NSImage], InAppNotificationSettings, Bool), NoError> in
                return screenLocked.get()
                    |> take(1)
                    |> map { data in return (sources, images, inAppSettings, data.isLocked)}
            }
            |> mapToSignal { sources, images, inAppSettings, screenIsLocked -> Signal<([Source], [MessageId:NSImage], InAppNotificationSettings, Bool, Peer, [String: NotificationPresentation], [(PeerMessageSound, String?)]), NoError> in
                if sources.isEmpty {
                    return .complete()
                }
                return account.postbox.loadedPeerWithId(account.peerId) |> mapToSignal { accountPeer in
                    return account.postbox.transaction { transaction -> [String: NotificationPresentation] in
                        let globalSettings = transaction.getPreferencesEntry(key: PreferencesKeys.globalNotifications)?.get(GlobalNotificationSettings.self)?.effective ?? GlobalNotificationSettingsSet.defaultSettings
                        var result: [String: NotificationPresentation] = [:]
                        for source in sources {
                            for message in source.messages {
                                result[source.key(for: message)] = notificationPresentation(source: source, message: message, globalSettings: globalSettings, peerSettings: transaction.getPeerNotificationSettings(id: message.id.peerId) as? TelegramPeerNotificationSettings)
                            }
                        }
                        return result
                    } |> mapToSignal { presentations in
                        var sounds: [PeerMessageSound] = []
                        for presentation in presentations.values where !sounds.contains(presentation.sound) {
                            sounds.append(presentation.sound)
                        }
                        let paths: [Signal<(PeerMessageSound, String?), NoError>] = sounds.map { sound in
                            switch sound {
                            case .none:
                                return .single((sound, nil))
                            case .default:
                                return getNotificationToneFile(account: account, sound: inAppSettings.tone) |> map { (sound, $0) }
                            default:
                                return getNotificationToneFile(account: account, sound: sound)
                                |> timeout(3.0, queue: Queue.concurrentDefaultQueue(), alternate: getNotificationToneFile(account: account, sound: inAppSettings.tone))
                                |> map { (sound, $0) }
                            }
                        }
                        return combineLatest(paths) |> take(1) |> map { paths in
                            return (sources, images, inAppSettings, screenIsLocked, accountPeer, presentations, paths)
                        }
                    }
                }
            } |> deliverOnMainQueue).start(next: { sources, images, inAppSettings, screenIsLocked, accountPeer, presentations, soundPaths in
                
                if !primary, !inAppSettings.notifyAllAccounts {
                    return
                }

                for source in sources {
                    loop: for message in source.messages {
                        
                        if alreadyNotified.contains(source.key(for: message)) {
                            continue
                        }

                        if message.isImported {
                            continue
                        }
                        let presentation = presentations[source.key(for: message)] ?? NotificationPresentation(muted: false, sound: .default, showPreview: true, hideSender: false)
                        if presentation.muted {
                            if message.consumableMention == nil {
                                continue
                            }
                        }
                        if let thread = source.threadData, thread.notificationSettings.isMuted {
                            if message.consumableMention == nil {
                                continue
                            }
                        }
                        
                        if message.author?.id != account.peerId || message.wasScheduled {
                            if !self.shouldPresent(accountId: account.id, wasScheduled: message.wasScheduled) {
                                let notifiedKey = source.key(for: message)
                                if alreadyNotified.insert(notifiedKey).inserted {
                                    alreadyNotifiedOrder.append(notifiedKey)
                                    if alreadyNotifiedOrder.count > 1000 {
                                        alreadyNotified.remove(alreadyNotifiedOrder.removeFirst())
                                    }
                                }
                                continue
                            }
                            var title:String = message.author?.displayTitle ?? ""
                            var hasReplyButton:Bool = !screenIsLocked
                            if let peer = message.peers[message.id.peerId] {
                                if peer.isSupergroup || peer.isGroup {
                                    title = peer.displayTitle
                                    hasReplyButton = peer.canSendMessage(false, threadData: source.threadData)
                                } else if message.id.peerId == repliesPeerId {
                                    if let peerId = message.sourceReference?.messageId.peerId, let sourcePeer = message.peers[peerId] {
                                        hasReplyButton = sourcePeer.canSendMessage(true, threadData: source.threadData)
                                    }
                                } else if peer.isChannel {
                                    hasReplyButton = false
                                }
                            }
                            
                            if message.wasScheduled {
                                hasReplyButton = false
                            }
                            
                            if screenIsLocked {
                                title = appName
                            }
                            
                            var text: String
                            var subText:String? = nil
                            switch source {
                            case let .reaction(message, peer, value, _, file, _):
                                
                                let reactionText: String
                                switch value {
                                case let .builtin(emoji):
                                    reactionText = emoji.normalizedEmoji
                                case let .custom(fileId):
                                    let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                                    let file = file ?? message.associatedMedia[mediaId] as? TelegramMediaFile
                                    reactionText = (file?.customEmojiText ?? file?.stickerText ?? "").normalizedEmoji
                                case .stars:
                                    reactionText = "⭐️"
                                }
                                
                                let msg = pullText(from: message).string as String
                                title = message.peers[message.id.peerId]?.displayTitle ?? ""
                                if message.id.peerId.namespace == Namespaces.Peer.CloudUser {
                                    text = strings().notificationContactReacted(reactionText.fixed, msg)
                                } else {
                                    text = strings().notificationGroupReacted(peer.displayTitle, reactionText.fixed, msg)
                                }
                            case .messages:
                                text = chatListText(account: account, for: message, applyUserName: true, notifications: true).string
                                if text.contains("\r") {
                                    let parts = text.components(separatedBy: "\r")
                                    text = parts[1]
                                    subText = parts[0]
                                }
                            }
                           
                            
                            if message.wasScheduled {
                                if message.id.peerId == account.peerId {
                                    title = strings().notificationReminder
                                } else {
                                    title = "📆 \(title)"
                                }
                                subText = nil
                            }
                            if message.id.peerId == repliesPeerId {
                                subText = message.chatPeer(account.peerId)?.displayTitle
                            }
                            
                            if let threadData = source.threadData, let txt = subText {
                                subText = "\(txt) → \(threadData.info.title)"
                            }
                            
                            switch source {
                            case .reaction:
                                if presentation.hideSender {
                                    title = appName
                                }
                                if presentation.hideSender || !inAppSettings.displayPreviews || screenIsLocked {
                                    text = strings().notificationReactionHidden
                                    subText = nil
                                }
                            case .messages:
                                if !inAppSettings.displayPreviews || !presentation.showPreview || message.peers[message.id.peerId] is TelegramSecretChat || screenIsLocked {
                                    text = strings().notificationLockedPreview
                                    subText = nil
                                }
                            }
                            
                            let notification = NSUserNotification()
                            
                            notification.identifier = "msg_\(message.id.string)"
                            
                            
                            let soundPath = soundPaths.first(where: { $0.0 == presentation.sound })?.1
                            if #available(macOS 10.14, *) {
                                switch inAppSettings.tone {
                                case .none:
                                    notification.soundName = nil
                                default:
                                    notification.soundName = soundPath
                                }
                            } else {
                                switch inAppSettings.tone {
                                case .none:
                                    notification.soundName = nil
                                default:
                                    break
                                }
                            }

                            if case .messages = source, message.muted {
                                notification.soundName = nil
                                title += " 🔕"
                            }
                           
                            if screenIsLocked {
                                notification.soundName = nil
                            }
                                                        
                            if self.activeAccounts.accounts.count > 1 && !screenIsLocked {
                                title += " → \(accountPeer.addressName ?? accountPeer.displayTitle)"
                            }
                                                        
                            notification.title = title
                            notification.informativeText = text as String
                            notification.subtitle = subText
                            notification.contentImage = screenIsLocked || presentation.hideSender ? nil : images[message.id]
                            notification.hasReplyButton = hasReplyButton
                            
                            notification.hasActionButton = !message.wasScheduled
                            notification.otherButtonTitle = strings().notificationMarkAsRead
                            
                            var dict: [String : Any] = [:]
                            
                            if message.wasScheduled {
                                dict["wasScheduled"] = true
                            }
                            
                            if let sourceReference = message.sourceReference, message.id.peerId == repliesPeerId {
                                dict["source.message.id"] = sourceReference.messageId.id
                                dict["source.message.namespace"] = sourceReference.messageId.namespace
                                dict["source.peer.id"] = sourceReference.messageId.peerId.id._internalGetInt64Value()
                                dict["source.peer.namespace"] = sourceReference.messageId.peerId.namespace._internalGetInt32Value()
                            }
                            if message.sourceReference != nil || source.threadData != nil {
                                dict["is_thread"] = true
                            }
                            if let threadId = message.replyAttribute?.threadMessageId {
                                dict["thread.message.id"] = threadId.id
                                dict["thread.message.namespace"] = threadId.namespace
                                dict["thread.peer.id"] = threadId.peerId.id._internalGetInt64Value()
                                dict["thread.peer.namespace"] = threadId.peerId.namespace._internalGetInt32Value()
                            } else if message.threadId == 1 {
                                dict["thread.message.id"] = 1
                                dict["thread.message.namespace"] = message.id.namespace
                                dict["thread.peer.id"] = message.id.peerId.id._internalGetInt64Value()
                                dict["thread.peer.namespace"] = message.id.peerId.namespace._internalGetInt32Value()
                            }
                            if let threadData = source.threadData, let data = CodableEntry(threadData)?.data {
                                dict["thread_data"] = data
                            }
                            
                            dict["reply.message.id"] =  message.id.id
                            dict["reply.message.namespace"] =  message.id.namespace
                            dict["reply.peer.id"] =  message.id.peerId.id._internalGetInt64Value()
                            dict["reply.peer.namespace"] =  message.id.peerId.namespace._internalGetInt32Value()
                            
                            if let groupId = source.groupId {
                                dict["groupId"] = groupId.rawValue
                            }
                            
                            dict["accountId"] = account.id.int64
                            dict["timestamp"] = Int32(Date().timeIntervalSince1970)

                            let notifiedKey = source.key(for: message)
                            if alreadyNotified.insert(notifiedKey).inserted {
                                alreadyNotifiedOrder.append(notifiedKey)
                                if alreadyNotifiedOrder.count > 1000 {
                                    alreadyNotified.remove(alreadyNotifiedOrder.removeFirst())
                                }
                            }
                            
                            notification.userInfo = dict
                            
                            self.deliver(notification)
                        }
                    }
                }
            }), forKey: account.id)
        
        startStoryNotifyListener(with: account, primary: primary)
    }
    
    private func deliver(_ notification: NSUserNotification) {
        _ = UNUserNotifications.authorizationStatus.start(next: { status in
            switch status {
            case .authorized:
                UNUserNotifications.current?.add(notification)
            case .notDetermined:
                UNUserNotifications.current?.authorize { manager in
                    manager.add(notification)
                }
            default:
                break
            }
        })
    }
    
    private struct StoryNotification {
        let peer: EnginePeer
        let hideSender: Bool
        let sound: PeerMessageSound
    }
    
    private func startStoryNotifyListener(with account: Account, primary: Bool) {
        let engine = TelegramEngine(account: account)
        let screenLocked = self.screenLocked
        let accountManager = self.accountManager
        let knownTimestamps = Atomic<[PeerId: Int32]?>(value: nil)
        
        let newStoryPeers: Signal<[EnginePeer], NoError> = engine.messages.storySubscriptions(isHidden: false) |> map { subscriptions -> [EnginePeer] in
            var current: [PeerId: Int32] = [:]
            for item in subscriptions.items {
                current[item.peer.id] = item.lastTimestamp
            }
            guard let previous = knownTimestamps.swap(current) else {
                return []
            }
            let minTimestamp = Int32(Date().timeIntervalSince1970) - 60
            return subscriptions.items.filter { item in
                return item.peer.id != account.peerId && item.hasUnseen && item.lastTimestamp >= minTimestamp && item.lastTimestamp > (previous[item.peer.id] ?? 0)
            }.map { $0.peer }
        } |> filter { !$0.isEmpty }
        
        let topPeerIds: Signal<Set<PeerId>, NoError> = engine.peers.recentPeers() |> take(1) |> map { recentPeers in
            guard case let .peers(peers) = recentPeers else {
                return Set()
            }
            return Set(peers.prefix(5).map { $0.id })
        }
        
        let signal = newStoryPeers |> mapToQueue { peers -> Signal<([StoryNotification], InAppNotificationSettings, Bool, Peer, [PeerId: NSImage], [(PeerMessageSound, String?)]), NoError> in
            return combineLatest(appNotificationSettings(accountManager: accountManager) |> take(1), topPeerIds, screenLocked.get() |> take(1), account.postbox.loadedPeerWithId(account.peerId) |> take(1)) |> mapToSignal { inAppSettings, topPeerIds, lockData, accountPeer in
                guard inAppSettings.enabled && inAppSettings.muteUntil < Int32(Date().timeIntervalSince1970) else {
                    return .complete()
                }
                return account.postbox.transaction { transaction -> [StoryNotification] in
                    let globalSettings = transaction.getPreferencesEntry(key: PreferencesKeys.globalNotifications)?.get(GlobalNotificationSettings.self)?.effective ?? GlobalNotificationSettingsSet.defaultSettings
                    let globalStorySettings = globalSettings.privateChats.storySettings
                    var result: [StoryNotification] = []
                    for peer in peers {
                        let storySettings = (transaction.getPeerNotificationSettings(id: peer.id) as? TelegramPeerNotificationSettings)?.storySettings ?? PeerStoryNotificationSettings.default
                        let enabled: Bool
                        switch storySettings.mute {
                        case .muted:
                            enabled = false
                        case .unmuted:
                            enabled = true
                        case .default:
                            switch globalStorySettings.mute {
                            case .muted:
                                enabled = false
                            case .unmuted:
                                enabled = true
                            case .default:
                                enabled = topPeerIds.contains(peer.id)
                            }
                        }
                        if !enabled {
                            continue
                        }
                        let hideSender: Bool
                        switch storySettings.hideSender {
                        case .hide:
                            hideSender = true
                        case .show:
                            hideSender = false
                        case .default:
                            hideSender = globalStorySettings.hideSender == .hide
                        }
                        let sound = storySettings.sound != .default ? storySettings.sound : effectiveCategorySound(globalStorySettings.sound)
                        result.append(StoryNotification(peer: peer, hideSender: hideSender, sound: sound))
                    }
                    return result
                } |> mapToSignal { notifications -> Signal<([StoryNotification], InAppNotificationSettings, Bool, Peer, [PeerId: NSImage], [(PeerMessageSound, String?)]), NoError> in
                    if notifications.isEmpty {
                        return .complete()
                    }
                    let photos: [Signal<(PeerId, CGImage?), NoError>] = notifications.map { notification in
                        let peer = notification.peer._asPeer()
                        return peerAvatarImage(account: account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, peer.displayLetters, nil, nil), genCap: false) |> take(1) |> map { (peer.id, $0.0) }
                    }
                    var sounds: [PeerMessageSound] = []
                    for notification in notifications where !sounds.contains(notification.sound) {
                        sounds.append(notification.sound)
                    }
                    let deviceTone = getNotificationToneFile(account: account, sound: inAppSettings.tone)
                    |> timeout(3.0, queue: Queue.concurrentDefaultQueue(), alternate: .single("default"))
                    let paths: [Signal<(PeerMessageSound, String?), NoError>] = sounds.map { sound in
                        switch sound {
                        case .none:
                            return .single((sound, nil))
                        case .default:
                            return deviceTone |> map { (sound, $0) }
                        default:
                            return getNotificationToneFile(account: account, sound: sound)
                            |> timeout(3.0, queue: Queue.concurrentDefaultQueue(), alternate: deviceTone)
                            |> map { (sound, $0) }
                        }
                    }
                    return combineLatest(combineLatest(photos), combineLatest(paths)) |> take(1) |> map { photos, paths in
                        var images: [PeerId: NSImage] = [:]
                        for (peerId, image) in photos {
                            if let image = image {
                                images[peerId] = NSImage(cgImage: image, size: NSMakeSize(50, 50))
                            }
                        }
                        return (notifications, inAppSettings, lockData.isLocked, accountPeer, images, paths)
                    }
                }
            }
        }
        
        storyDisposableDict.set((signal |> deliverOnMainQueue).start(next: { [weak self] notifications, inAppSettings, screenIsLocked, accountPeer, images, soundPaths in
            guard let self else {
                return
            }
            if !primary, !inAppSettings.notifyAllAccounts {
                return
            }
            if !self.shouldPresent(accountId: account.id, wasScheduled: false) {
                return
            }
            for story in notifications {
                let hidden = story.hideSender || screenIsLocked
                var title = hidden ? appName : story.peer._asPeer().displayTitle
                if self.activeAccounts.accounts.count > 1 && !screenIsLocked {
                    title += " → \(accountPeer.addressName ?? accountPeer.displayTitle)"
                }
                let notification = NSUserNotification()
                notification.identifier = "story_\(story.peer.id.toInt64())"
                notification.title = title
                notification.informativeText = hidden ? strings().notificationStoryHidden : strings().notificationStoryPosted
                notification.contentImage = hidden ? nil : images[story.peer.id]
                notification.hasReplyButton = false
                notification.hasActionButton = false
                if #available(macOS 10.14, *), !screenIsLocked {
                    switch inAppSettings.tone {
                    case .none:
                        notification.soundName = nil
                    default:
                        notification.soundName = soundPaths.first(where: { $0.0 == story.sound })?.1
                    }
                }
                notification.userInfo = [
                    "story.peer.id": story.peer.id.id._internalGetInt64Value(),
                    "story.peer.namespace": story.peer.id.namespace._internalGetInt32Value(),
                    "accountId": account.id.int64,
                    "timestamp": Int32(Date().timeIntervalSince1970)
                ]
                self.deliver(notification)
            }
        }), forKey: account.id)
    }

  
    private func shouldPresent(accountId: AccountRecordId, wasScheduled: Bool) -> Bool {
        if accountId != self.activeAccounts.primary?.id {
            return true
        }
        
        guard let context = find(accountId) else {
            return false
        }
        let result = !showNotificationsOutOfFocus || !context.window.isKeyWindow || wasScheduled
        
        return result
    }

    
}
