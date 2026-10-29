import Cocoa
import TelegramCore
import Localization
import SwiftSignalKit
import Postbox
import ObjcUtils
import Strings
import WebKit

public func clearUserDefaultsObject(forKeyPrefix prefix: String) {
    let defaults = UserDefaults.standard
    let keys = defaults.dictionaryRepresentation().keys
    
    for key in keys {
        if key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}






public enum SendingType :String {
    case enter = "enter"
    case cmdEnter = "cmdEnter"
}

public enum EntertainmentState : Int32 {
    case emoji = 0
    case stickers = 1
    case gifs = 2
}

public enum RecordingStateSettings : Int32 {
    case voice = 0
    case video = 1
}

public enum ForceTouchAction: Int32 {
    case edit
    case reply
    case forward
    case previewMedia
    case react
}

public enum BotPemissionKey: String {
    case contact = "PermissionInlineBotContact"
}


public enum AppTooltip {
    case voiceRecording
    case videoRecording
    case pauseRecording
    case mediaPreview_archive
    case mediaPreview_collage
    case mediaPreview_media
    case mediaPreview_file
    fileprivate var localizedString: String {
        switch self {
        case .voiceRecording:
            return strings().appTooltipVoiceRecord
        case .pauseRecording:
            return strings().appTooltipPauseRecording
        case .videoRecording:
            return strings().appTooltipVideoRecord
        case .mediaPreview_archive:
            return strings().previewSenderArchiveTooltip
        case .mediaPreview_collage:
            return strings().previewSenderCollageTooltip
        case .mediaPreview_media:
            return strings().previewSenderMediaTooltip
        case .mediaPreview_file:
            return strings().previewSenderFileTooltip
        }
    }
    
    private var version:Int {
        return 1
    }
    
    fileprivate var key: String {
        switch self {
        case .voiceRecording:
            return "app_tooltip_voice_recording_" + "\(version)"
        case .pauseRecording:
            return "app_tooltip_pause_recording_" + "\(version)"
        case .videoRecording:
            return "app_tooltip_video_recording_" + "\(version)"
        case .mediaPreview_archive:
             return "app_tooltip_mediaPreview_archive_" + "\(version)"
        case .mediaPreview_collage:
             return "app_tooltip_mediaPreview_collage_" + "\(version)"
        case .mediaPreview_media:
             return "app_tooltip_mediaPreview_media_" + "\(version)"
        case .mediaPreview_file:
             return "app_tooltip_mediaPreview_file_" + "\(version)"
        }
    }
    
    fileprivate var showCount: Int {
        return 4
    }
    
}

public func getAppTooltipLimited(for value: AppTooltip, callback: (String) -> Void) {
    guard UserDefaults.standard.integer(forKey: value.key) < value.showCount else {
        return
    }
    getAppTooltip(for: value, callback: callback)
}

public func getAppTooltip(for value: AppTooltip, callback: (String) -> Void) {
    let shownCount: Int = UserDefaults.standard.integer(forKey: value.key)
    UserDefaults.standard.set(shownCount + 1, forKey: value.key)
    UserDefaults.standard.synchronize()
    callback(value.localizedString)
}

public class FastSettings {
    private static let kVideoQuality = "kVideoQuality"

    private static let kSendingType = "kSendingType"
    private static let kEntertainmentType = "kEntertainmentType"
    private static let kSidebarType = "kSidebarType1"
    private static let kSidebarShownType = "kSidebarShownType2"
    private static let kDebugWebApp = "kDebugWebApp"
    private static let kRecordingStateType = "kRecordingStateType"
    private static let kInAppSoundsType = "kInAppSoundsType"
    private static let kIsMinimisizeType = "kIsMinimisizeType"
    private static let kAutomaticConvertEmojiesType = "kAutomaticConvertEmojiesType2"
    private static let kSuggestSwapEmoji = "kSuggestSwapEmoji"
    private static let kForceTouchAction = "kForceTouchAction"
    private static let kNeedCollage = "kNeedCollage"
	private static let kInstantViewScrollBySpace = "kInstantViewScrollBySpace"
    private static let kAutomaticallyPlayGifs = "kAutomaticallyPlayGifs"
    private static let kArchiveIsHidden = "kArchiveIsHidden"
    private static let kRTFEnable = "kRTFEnable";
    private static let kNeedShowChannelIntro = "kNeedShowChannelIntro"
    
    private static let kNoticeAdChannel = "kNoticeAdChannel"
    private static let kPlayingRate = "kPlayingRate2"
    private static let kPlayingMusicRate = "kPlayingMusicRate"
    private static let kPlayingVideoRate = "kPlayingVideoRate"

    private static let kSVCShareMicro = "kSVCShareMicro"

    private static let kReactionsMode = "kReactionsMode"

    private static let kVolumeRate = "kVolumeRate"
    private static let kStoryVolumeRate = "kStoryVolumeRate"

    private static let kArchiveAutohidden = "kArchiveAutohidden"
    private static let kAutohideArchiveFeature = "kAutohideArchiveFeature"

    private static let kLeftColumnWidth = "kLeftColumnWidth"

    private static let kShowEmptyTips = "kShowEmptyTips"

    
    private static let kConfirmWebApp = "kConfirmWebApp"

    private static let kAnimateInputEmoji = "kAnimateInputEmoji"
    private static let kUseNativeGraphicContext = "kUseNativeGraphicContext"

    
    private static let kPhotoSize = "kPhotoSize"

    
    private static let kStoryMuted = "kStoryMuted"
    private static let kStoryHD = "kStoryHD"
    
    private static let kHashtagChannel = "kHashtagChannel";
    
    
    private static let kContactsSort = "kContactsSort";
    
    private static let kAgeVerification = "kAgeVerification2";
    
    public static var contactsSort: ContactsSort {
        get {
            if let value = UserDefaults.standard.value(forKey: kContactsSort) as? Int32 {
                return .init(rawValue: value) ?? .lastSeen
            } else {
                return .lastSeen
            }
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: kContactsSort)
        }
    }


    public static var hasHashtagChannelBadge: Bool {
        get {
            return UserDefaults.standard.bool(forKey: kHashtagChannel)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: kHashtagChannel)
        }
    }
    
    public static var sendingType:SendingType {
        let type = UserDefaults.standard.value(forKey: kSendingType) as? String
        if let type = type {
            return SendingType(rawValue: type) ?? .enter
        }
        return .enter
    }
    
    
    public static var entertainmentState:EntertainmentState {
        return EntertainmentState(rawValue: Int32(UserDefaults.standard.integer(forKey: kEntertainmentType))) ?? .emoji
    }
    
    public static func changeEntertainmentState(_ state:EntertainmentState) {
        UserDefaults.standard.set(state.rawValue, forKey: kEntertainmentType)
        UserDefaults.standard.synchronize()
    }
    
    public static func changeSendingType(_ type:SendingType) {
        UserDefaults.standard.set(type.rawValue, forKey: kSendingType)
        UserDefaults.standard.synchronize()
    }
    
    public static func checkSendingAbility(for event:NSEvent) -> Bool {
        return isEnterAccessObjc(event, sendingType == .cmdEnter)
    }
    
    public static func isChannelMessagesMuted(_ peerId: PeerId) -> Bool {
        return UserDefaults.standard.bool(forKey: "\(peerId)_m_muted")
    }
    
    public static func toggleChannelMessagesMuted(_ peerId: PeerId) -> Void {
        UserDefaults.standard.set(!isChannelMessagesMuted(peerId), forKey: "\(peerId)_m_muted")
    }
    
    public static func monoforumState(_ peerId: PeerId) -> MonoforumUIState {
        let int = UserDefaults.standard.integer(forKey: "\(peerId)_monoforum_state")
        return MonoforumUIState(rawValue: int) ?? .vertical
    }
    
    public static func setMonoforumState(_ peerId: PeerId, state: MonoforumUIState) -> Void {
        UserDefaults.standard.set(state.rawValue, forKey: "\(peerId)_monoforum_state")
    }

    
    public static var photoDimension: CGFloat {
        if let largePhotos = UserDefaults.standard.value(forKey: kPhotoSize) as? Bool {
            return largePhotos ? 2560 : 1280
        } else {
            return 1280
        }
    }
    
    public static var sendLargePhotos: Bool {
        return UserDefaults.standard.bool(forKey: kPhotoSize)
    }
    
    public static func sendLargePhotos(_ value: Bool) {
        UserDefaults.standard.setValue(value, forKey: kPhotoSize)
    }

    
    public static func needConfirmPaid(_ peerId: PeerId, price: Int) -> Bool {
        return UserDefaults.standard.bool(forKey: "\(peerId)_confirm_paid_\(price)_4")
    }
    
    public static func toggleCofirmPaid(_ peerId: PeerId, price: Int) -> Void {
        UserDefaults.standard.set(!needConfirmPaid(peerId, price: price), forKey: "\(peerId)_confirm_paid_\(price)_4")
    }
    
    public static func shouldConfirmWebApp(_ peerId: PeerId) -> Bool {
        let value = UserDefaults.standard.value(forKey: "\(peerId)_\(kConfirmWebApp)")
        return value as? Bool ?? true
    }
    
    public static func markWebAppAsConfirmed(_ peerId: PeerId) -> Void {
        UserDefaults.standard.set(false, forKey: "\(peerId)_\(kConfirmWebApp)")
    }
    
    @available(macOS 12.0, *)
    public static func botAccessTo(_ type: WKMediaCaptureType, peerId: PeerId) -> Bool {
        let value = UserDefaults.standard.value(forKey: "wk2_bot_access_\(type.rawValue)_\(peerId.toInt64())") as? Bool
        
        if let value = value {
            return value
        } else {
            return false
        }
    }
    
    public static func allowBotAccessToBiometric(peerId: PeerId, accountId: PeerId) {
        FastSettings.setBotAccessToBiometricRequested(peerId: peerId, accountId: accountId)
        UserDefaults.standard.setValue(true, forKey: "_biometric_bot_\(peerId.toInt64())_\(accountId.toInt64())")
        UserDefaults.standard.synchronize()
    }
    public static func setBotAccessToBiometricRequested(peerId: PeerId, accountId: PeerId) {
        UserDefaults.standard.setValue(true, forKey: "_biometric_bot_\(peerId.toInt64())_requested_\(accountId.toInt64())")
        UserDefaults.standard.synchronize()
    }
    
    
    @available(macOS 12.0, *)
    public static func allowBotAccessTo(_ type: WKMediaCaptureType, peerId: PeerId) {
        UserDefaults.standard.setValue(true, forKey: "wk2_bot_access_\(type.rawValue)_\(peerId.toInt64())")
        UserDefaults.standard.synchronize()
    }
    
        
    public static var playingRate: Double {
        let double = UserDefaults.standard.double(forKey: kPlayingRate)
        if double == 0 {
            return 1.0
        }
        return min(max(double, 0.2), 2.5)
    }
    
    public static func setPlayingRate(_ rate: Double) {
        UserDefaults.standard.set(rate, forKey: kPlayingRate)
    }
    
    public static var playingMusicRate: Double {
        let double = UserDefaults.standard.double(forKey: kPlayingMusicRate)
        if double == 0 {
            return 1.0
        }
        return min(max(double, 0.2), 2.5)
    }
    
    public static func setPlayingMusicRate(_ rate: Double) {
        UserDefaults.standard.set(rate, forKey: kPlayingMusicRate)
    }
    
    public static var playingVideoRate: Double {
        let double = UserDefaults.standard.double(forKey: kPlayingVideoRate)
        if double == 0 {
            return 1.0
        }
        return min(max(double, 0.2), 2.5)
    }
    
    public static func setPlayingVideoRate(_ rate: Double) {
        UserDefaults.standard.set(rate, forKey: kPlayingVideoRate)
    }
    
    public static var volumeRate: Float {
        if UserDefaults.standard.value(forKey: kVolumeRate) != nil {
            return min(max(UserDefaults.standard.float(forKey: kVolumeRate), 0), 1)
        } else {
            return 0.8
        }
    }
    
    public static var volumeStoryRate: Float {
        if UserDefaults.standard.value(forKey: kStoryVolumeRate) != nil {
            return min(max(UserDefaults.standard.float(forKey: kStoryVolumeRate), 0), 1)
        } else {
            return 0.8
        }
    }
    
    public static func setStoryVolumeRate(_ rate: Float) {
        UserDefaults.standard.set(rate, forKey: kStoryVolumeRate)
    }
    
    public static func setVolumeRate(_ rate: Float) {
        UserDefaults.standard.set(rate, forKey: kVolumeRate)
    }
    
    public static var isMinimisize: Bool {
        get {
            return UserDefaults.standard.bool(forKey: kIsMinimisizeType)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kIsMinimisizeType)
        }
    }
    public static var accessibilityTreeEnabled: Bool {
        get {
            return UserDefaults.standard.object(forKey: "kAccessibilityTreeEnabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAccessibilityTreeEnabled")
        }
    }

    public static var accessibilityServerDisabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "kAccessibilityServerDisabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kAccessibilityServerDisabled")
        }
    }

    public static var accessibilityTreeEffective: Bool {
        return accessibilityTreeEnabled && !accessibilityServerDisabled
    }

    public static var canViewPeerId: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "kCanViewPeerId")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "kCanViewPeerId")
        }
    }
    
    
    
    public static var sidebarEnabled:Bool {
        return UserDefaults.standard.bool(forKey: kSidebarType)
    }
    
    public static var sidebarShown: Bool {
        return !UserDefaults.standard.bool(forKey: kSidebarShownType)
    }
    
    public static var debugWebApp: Bool {
        return UserDefaults.standard.bool(forKey: kDebugWebApp)
    }
    
    public static func toggleDebugWebApp() {
        UserDefaults.standard.set(!debugWebApp, forKey: kDebugWebApp)
        
    }
    
    public static var recordingState: RecordingStateSettings {
        return RecordingStateSettings(rawValue: Int32(UserDefaults.standard.integer(forKey: kRecordingStateType))) ?? .voice
    }
    
    public static var isNeedCollage: Bool {
        get {
            if UserDefaults.standard.value(forKey: kNeedCollage) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: kNeedCollage)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kNeedCollage)
            UserDefaults.standard.synchronize()
        }
    }
    
    public static var enableRTF: Bool {
        set {
            UserDefaults.standard.set(!newValue, forKey: kRTFEnable)
            UserDefaults.standard.synchronize()
        }
        get {
             return !UserDefaults.standard.bool(forKey: kRTFEnable)
        }
    }
    
    public static func updateVCShareMicro(_ value: Bool) {
        UserDefaults.standard.setValue(value, forKey: kSVCShareMicro)
    }
    
    public static var emptyTips: Bool {
        if let value = UserDefaults.standard.value(forKey: kShowEmptyTips) as? Bool {
            return value
        }
        return true
    }
    public static func updateEmptyTips(_ value: Bool) {
        UserDefaults.standard.setValue(value, forKey: kShowEmptyTips)
    }
    
    public static func systemUnsupported(_ time: Int32?) -> Bool {
        if #available(macOS 10.13, *) {
            return false
        } else {
            if let time = time {
                return time < Int(Date().timeIntervalSince1970)
            } else {
                return true
            }
        }
    }
    
    public static func toggleRecordingState() {
        UserDefaults.standard.set((recordingState == .voice ? RecordingStateSettings.video : RecordingStateSettings.voice).rawValue, forKey: kRecordingStateType)
    }
    
    public static var needShowChannelIntro: Bool {
        return !UserDefaults.standard.bool(forKey: kNeedShowChannelIntro)
    }
    
    public static func markChannelIntroHasSeen() {
        UserDefaults.standard.set(true, forKey: kNeedShowChannelIntro)
    }
    
    public static var lastAgeVerification: TimeInterval? {
        get {
            return UserDefaults.standard.value(forKey: kAgeVerification) as? TimeInterval
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kAgeVerification)
        }
    }
    
    public static var forceTouchAction: ForceTouchAction {
        if UserDefaults.standard.value(forKey: kForceTouchAction) != nil {
            return ForceTouchAction(rawValue: Int32(UserDefaults.standard.integer(forKey: kForceTouchAction))) ?? .react
        } else {
            return .react
        }
    }
    
    public static func toggleForceTouchAction(_ action: ForceTouchAction) {
        UserDefaults.standard.set(action.rawValue, forKey: kForceTouchAction)
        UserDefaults.standard.synchronize()
    }
    
    public static func craftAboutShownCountAndIncrement() -> Int {
        let value = UserDefaults.standard.integer(forKey: "craft_about_shown_count")
        UserDefaults.standard.set(value + 1, forKey: "craft_about_shown_count")
        return value
    }

    public static func disableSharingModalShownCountAndIncrement() -> Int {
        let value = UserDefaults.standard.integer(forKey: "disable_sharing_modal_shown_count_v4")
        UserDefaults.standard.set(value + 1, forKey: "disable_sharing_modal_shown_count_v4")
        return value
    }
    
    public static func openInQuickLook(_ ext: String) -> Bool {
        return !UserDefaults.standard.bool(forKey: "open_in_quick_look_\(ext)")
    }
    public static func toggleSidebarShown(_ enable: Bool) {
        UserDefaults.standard.set(!enable, forKey: kSidebarShownType)
        UserDefaults.standard.synchronize()
    }

    public static func toggleSidebar(_ enable: Bool) {
        UserDefaults.standard.set(enable, forKey: kSidebarType)
        UserDefaults.standard.synchronize()
    }
    
    public static func toggleInAppSouds(_ enable: Bool) {
        UserDefaults.standard.set(!enable, forKey: kInAppSoundsType)
        UserDefaults.standard.synchronize()
    }
    
    public static func toggleReactionMode(_ legacy: Bool) {
        UserDefaults.standard.set(legacy, forKey: kReactionsMode)
        UserDefaults.standard.synchronize()
    }
    
    public static var legacyReactions: Bool {
        UserDefaults.standard.bool(forKey: kReactionsMode)
    }
    
    public static var inAppSounds: Bool {
        return !UserDefaults.standard.bool(forKey: kInAppSoundsType)
    }
	
	public static func toggleInstantViewScrollBySpace(_ enable: Bool) {
		UserDefaults.standard.set(enable, forKey: kInstantViewScrollBySpace)
        UserDefaults.standard.synchronize()
	}
    
    public static func toggleAutomaticReplaceEmojies(_ enable: Bool) {
        UserDefaults.standard.set(!enable, forKey: kAutomaticConvertEmojiesType)
        UserDefaults.standard.synchronize()
    }
    
    public static var suggestSwapEmoji: Bool {
        if let value = UserDefaults.standard.value(forKey: kSuggestSwapEmoji) as? Bool {
            return value
        }
        return true
    }
    public static func toggleSwapEmoji(_ value: Bool) -> Void {
        UserDefaults.standard.setValue(value, forKey: kSuggestSwapEmoji)
        UserDefaults.standard.synchronize()
    }
    
    public static var isPossibleReplaceEmojies: Bool {
        return !UserDefaults.standard.bool(forKey: kAutomaticConvertEmojiesType)
    }
	
	public static var instantViewScrollBySpace: Bool {
		return UserDefaults.standard.bool(forKey: kInstantViewScrollBySpace)
	}
    
    public static func toggleAutoPlayGifs(_ enable: Bool) {
        UserDefaults.standard.set(!enable, forKey: kAutomaticallyPlayGifs)
        UserDefaults.standard.synchronize()
    }
    
    public static var archiveStatus: ItemHideStatus {
        get {
            let value = UserDefaults.standard.integer(forKey: kArchiveIsHidden)
            return ItemHideStatus(rawValue: min(value, 3))!
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: kArchiveIsHidden)
            UserDefaults.standard.synchronize()
        }
    }
    
    public static func removePromoTitle(for peerId: PeerId) {
        UserDefaults.standard.set(false, forKey: "promo_\(peerId)_1")
        UserDefaults.standard.synchronize()
    }
    
    public static func isSecretChatWebPreviewAvailable(for accountId: Int64) -> Bool? {
        return UserDefaults.standard.value(forKey: "IsSecretChatWebPreviewAvailable_\(accountId)") as? Bool
    }
    
    public static func setSecretChatWebPreviewAvailable(for accountId: Int64, value: Bool) -> Void {
        UserDefaults.standard.set(value, forKey: "IsSecretChatWebPreviewAvailable_\(accountId)")
        UserDefaults.standard.synchronize()
    }
    
    public static var storyIsMuted: Bool {
        get {
            return UserDefaults.standard.value(forKey: kStoryMuted) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kStoryMuted)
        }
    }
    
    
    private static let kDefaultScreenShareKey = "kDefaultScreenShare"
    private static let kDefaultVideoShare = "kDefaultVideoShare"
    public static func defaultScreenShare() -> String? {
        return UserDefaults.standard.value(forKey: kDefaultScreenShareKey) as? String
    }
    public static func setDefaultScreenShare(_ uniqueId: String?) -> Void {
        if let uniqueId = uniqueId {
            UserDefaults.standard.set(uniqueId, forKey: kDefaultScreenShareKey)
        } else {
            UserDefaults.standard.removeObject(forKey: kDefaultScreenShareKey)
        }
        UserDefaults.standard.synchronize()
    }
    public static func defaultVideoShare() -> String? {
        return UserDefaults.standard.value(forKey: kDefaultVideoShare) as? String
    }
    public static func setDefaultVideoShare(_ uniqueId: String?) -> Void {
        if let uniqueId = uniqueId {
            UserDefaults.standard.set(uniqueId, forKey: kDefaultVideoShare)
        } else {
            UserDefaults.standard.removeObject(forKey: kDefaultVideoShare)
        }
        UserDefaults.standard.synchronize()
    }
    
    
    
    
    public static func updateLeftColumnWidth(_ width: CGFloat) {
        UserDefaults.standard.set(round(width), forKey: kLeftColumnWidth)
        UserDefaults.standard.synchronize()
    }
    public static var leftColumnWidth: CGFloat {
        return round(UserDefaults.standard.value(forKey: kLeftColumnWidth) as? CGFloat ?? 300)
    }
    
    public static func dismissPendingRequests(_ peerIds:[PeerId], for peerId: PeerId) {
        
        var peers = UserDefaults.standard.value(forKey: "pendingRequests2_\(peerId)") as? [Int64] ?? []
        peers.append(contentsOf: peerIds.map { $0.toInt64() })
        var seen = Set<Int64>()
        peers = peers.filter { seen.insert($0).inserted }
        
        UserDefaults.standard.set(peers, forKey: "pendingRequests2_\(peerId)")
        UserDefaults.standard.synchronize()
    }
    
    
    public static func canBeShownPendingRequests(_ peerIds:[PeerId], for peerId: PeerId) -> Bool {
        let peers = UserDefaults.standard.value(forKey: "pendingRequests2_\(peerId)") as? [Int64] ?? []
        
        let intersection = Set(peerIds.map { $0.toInt64() }).intersection(peers)
        return intersection.count != peerIds.count
    }
    
    public static var animateInputEmoji: Bool {
        return UserDefaults.standard.bool(forKey: kAnimateInputEmoji)
    }
    public static func toggleAnimateInputEmoji() {
        return UserDefaults.standard.set(!animateInputEmoji, forKey: kAnimateInputEmoji)
    }
    public static var useNativeGraphicContext: Bool {
        let value = UserDefaults.standard.value(forKey: kUseNativeGraphicContext) as? Bool
        return value ?? true
    }
    public static func toggleNativeGraphicContext() {
        return UserDefaults.standard.set(!useNativeGraphicContext, forKey: kUseNativeGraphicContext)
    }
    
    
    public static var premiumPerks:[String] {
        let perks = [PremiumValue.stories.rawValue,
                     PremiumValue.wallpapers.rawValue,
                     PremiumValue.peer_colors.rawValue,
                     PremiumValue.saved_tags.rawValue,
                     PremiumValue.last_seen.rawValue,
                     PremiumValue.message_privacy.rawValue,
                     PremiumValue.business.rawValue,
                     PremiumValue.folder_tags.rawValue,
                     PremiumValue.business_intro.rawValue,
                     PremiumValue.business_bots.rawValue,
                     PremiumValue.business_links.rawValue]
        let dismissedPerks = UserDefaults.standard.value(forKey: "dismissedPerks") as? [String] ?? []
        return perks.filter { !dismissedPerks.contains($0) }
    }
    public static func dismissPremiumPerk(_ string: String) {
        var dismissedPerks = UserDefaults.standard.value(forKey: "dismissedPerks") as? [String] ?? []
        dismissedPerks.append(string)
        UserDefaults.standard.setValue(dismissedPerks, forKey: "dismissedPerks")
    }
    
    public static func getUUID(_ id: Int64) -> UUID? {
        let stored = UserDefaults.standard.string(forKey: "_uuid_\(id)")
        if let stored = stored {
            return .init(uuidString: stored)
        } else {
            let uuid: UUID = UUID()
            UserDefaults.standard.setValue(uuid.uuidString, forKey: "_uuid_\(id)")
            return uuid
        }
    }
    
    public static func defaultUUID() -> UUID? {
        let stored = UserDefaults.standard.string(forKey: "_uuid_default")
        if let stored = stored {
            return .init(uuidString: stored)
        } else {
            let uuid: UUID = UUID()
            UserDefaults.standard.setValue(uuid.uuidString, forKey: "_uuid_default")
            return uuid
        }
    }
    
    public static func isDefaultAccount(_ id: Int64) -> Bool {
        let accountId = UserDefaults.standard.value(forKey: "_default_account_id")
        
        if let accountId = accountId as? Int64 {
            return accountId == id
        } else {
            UserDefaults.standard.setValue(id, forKey: "_default_account_id")
            return true
        }

    }
    
    public static func clear_uuid(_ id: Int64) {
        if #available(macOS 14.0, *) {
            if (FastSettings.getUUID(id)) != nil {
//                autoreleasepool {
//                    let configuration = WKWebViewConfiguration()
//                    configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
//                }
//                WKWebsiteDataStore.remove(forIdentifier: uuid, completionHandler: { _ in
//                })
            }
        }
    }
}

fileprivate let TelegramFileMediaBoxPath:String = "TelegramFileMediaBoxPathAttributeKey"







public extension String {
    var fixedFileName: String {
        var string = self.replacingOccurrences(of: "/", with: "_")

        var range = string.nsstring.range(of: ".")
        while range.location == 0 {
            string = string.nsstring.replacingCharacters(in: range, with: "_")
            range = string.nsstring.range(of: ".")
        }
        return string
    }
}

public func putFileToTemp(from:String, named:String) -> Signal<String?, NoError> {
    return Signal { subscriber in

        let name = named.fixedFileName
        guard !name.isEmpty, !name.contains("\0") else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let new = NSTemporaryDirectory() + name
        try? FileManager.default.removeItem(atPath: new)
        try? FileManager.default.copyItem(atPath: from, toPath: new)
        
        subscriber.putNext(new)
        subscriber.putCompletion()
        return EmptyDisposable
    }
}


