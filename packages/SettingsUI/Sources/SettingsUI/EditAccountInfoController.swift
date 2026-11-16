import Cocoa
import TGUIKit
import TelegramCore
import InputView
import Postbox
import SwiftSignalKit
import CalendarUtils
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FoundationUtils
import AvatarUI
import ShortPeerRow
import TelegramMediaUtils
import AvatarEditorUI
import PhoneNumberUtils
import FilePanels
import InlineStickerLayer
import AppAnalytics




public func editAccountUpdateBirthday(_ date: Date, context: any AccountContextProtocol) {
    let window = context.window
    _ = (context.engine.accountData.updateBirthday(birthday: date.birthday) |> deliverOnMainQueue).startStandalone(error: { [weak context, weak window] error in
        guard let context, let window, context.window === window else { return }
        switch error {
        case .flood:
            showModalText(for: context.window, text: strings().loginFloodWait)
        case .generic:
            showModalText(for: context.window, text: strings().unknownError)
        }
    }, completed: { [weak context, weak window] in
        guard let context, let window, context.window === window else { return }
        showModalText(for: window, text: strings().birthdayAlertAdded)
    })
}

public enum EditSettingsEntryTag: ItemListItemTag {
    case bio
    case username

    public func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? EditSettingsEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
    public var stableId: InputDataEntryId {
        switch self {
        case .bio:
            return .input(_id_about)
        case .username:
            return .general(_id_username)
        }
    }
}


private func valuesRequiringUpdate(state: EditInfoState, view: PeerView) -> ((fn: String, ln: String)?, about: String?) {
    if let peer = view.peers[view.peerId] as? TelegramUser {
        var names:(String, String)? = nil
        let pf = peer.firstName ?? ""
        let pl = peer.lastName ?? ""

        if state.firstName != pf || state.lastName != pl {
            names = (state.firstName, state.lastName)
        }
        var about: String? = nil
        
        if let cachedData = view.cachedData as? CachedUserData {
            if state.about != (cachedData.about ?? "") {
                about = state.about
            }
        } else if state.aboutEdited {
            about = state.about
        }
        
        return (names, about)
    }
    return (nil, nil)
}

private final class EditInfoControllerArguments {
    public let context: any AccountContextProtocol
    public let uploadNewPhoto:(Control)->Void
    public let logout:()->Void
    public let username:()->Void
    public let changeNumber:()->Void
    public let addAccount: ()->Void
    public let userNameColor: ()->Void
    public let birthday:()->Void
    public let openBirthdayPrivacy:()->Void
    public let removeBirthday:()->Void
    public let personalChannel:()->Void
    public let openHours:()->Void
    public let openLocation:()->Void
    public let chatAutomation:()->Void
    public init(context: any AccountContextProtocol, uploadNewPhoto:@escaping(Control)->Void, logout:@escaping()->Void, username: @escaping()->Void, changeNumber:@escaping()->Void, addAccount: @escaping() -> Void, userNameColor: @escaping()->Void, birthday:@escaping()->Void, openBirthdayPrivacy:@escaping()->Void, removeBirthday:@escaping()->Void, personalChannel:@escaping()->Void, openHours:@escaping()->Void, openLocation:@escaping()->Void, chatAutomation:@escaping()->Void) {
        self.context = context
        self.logout = logout
        self.username = username
        self.changeNumber = changeNumber
        self.uploadNewPhoto = uploadNewPhoto
        self.addAccount = addAccount
        self.userNameColor = userNameColor
        self.birthday = birthday
        self.openBirthdayPrivacy = openBirthdayPrivacy
        self.removeBirthday = removeBirthday
        self.personalChannel = personalChannel
        self.openHours = openHours
        self.openLocation = openLocation
        self.chatAutomation = chatAutomation
    }
}
public struct EditInfoState : Equatable {
    public static func == (lhs: EditInfoState, rhs: EditInfoState) -> Bool {
        
        if let lhsPeer = lhs.peer, let rhsPeer = rhs.peer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.peer != nil) != (rhs.peer != nil) {
            return false
        }
        
        return lhs.firstName == rhs.firstName && lhs.lastName == rhs.lastName && lhs.about == rhs.about && lhs.aboutEdited == rhs.aboutEdited && lhs.username == rhs.username && lhs.phone == rhs.phone && lhs.representation == rhs.representation && lhs.updatingPhotoState == rhs.updatingPhotoState && lhs.stateInited == rhs.stateInited && lhs.peerStatusSettings == rhs.peerStatusSettings
    }
    
    public let firstName: String
    public let lastName: String
    public let about: String
    public let aboutEdited: Bool
    public let username: String?
    public let phone: String?
    public let representation:TelegramMediaImageRepresentation?
    public let updatingPhotoState: PeerInfoUpdatingPhotoState?
    public let stateInited: Bool
    public let peer: Peer?
    public let peerStatusSettings: PeerStatusSettings?
    public let addToException: Bool
    public let birthday: TelegramBirthday?
    public let personalChannel: EnginePeer?
    public let hasBusinessHours: Bool
    public let hasBusinessLocation: Bool
    public let note: Updated_ChatTextInputState
    public init(stateInited: Bool = false, firstName: String = "", lastName: String = "", about: String = "", aboutEdited: Bool = false, username: String? = nil, phone: String? = nil, representation: TelegramMediaImageRepresentation? = nil, updatingPhotoState: PeerInfoUpdatingPhotoState? = nil, peer: Peer? = nil, peerStatusSettings: PeerStatusSettings? = nil, addToException: Bool = true, birthday: TelegramBirthday? = nil, personalChannel: EnginePeer? = nil, hasBusinessHours: Bool = false, hasBusinessLocation: Bool = false, note: Updated_ChatTextInputState = .init()) {
        self.firstName = firstName
        self.lastName = lastName
        self.about = about
        self.aboutEdited = aboutEdited
        self.username = username
        self.phone = phone
        self.representation = representation
        self.updatingPhotoState = updatingPhotoState
        self.stateInited = stateInited
        self.peer = peer
        self.peerStatusSettings = peerStatusSettings
        self.addToException = addToException
        self.birthday = birthday
        self.personalChannel = personalChannel
        self.hasBusinessHours = hasBusinessHours
        self.hasBusinessLocation = hasBusinessLocation
        self.note = note
    }
    
    public init(_ peerView: PeerView, context: any AccountContextProtocol) {
        let peer = peerView.peers[peerView.peerId] as? TelegramUser
        self.peer = peer
        self.firstName = peer?.firstName ?? ""
        self.lastName = peer?.lastName ?? ""
        self.username = peer?.usernames.first(where: { $0.isActive })?.username
        self.phone = peer?.phone
        self.about = (peerView.cachedData as? CachedUserData)?.about ?? ""
        self.aboutEdited = false
        self.representation = peer?.smallProfileImage
        self.updatingPhotoState = nil
        self.stateInited = true
        self.peerStatusSettings = (peerView.cachedData as? CachedUserData)?.peerStatusSettings
        self.addToException = true
        self.birthday = (peerView.cachedData as? CachedUserData)?.birthday
        self.personalChannel = nil
        self.hasBusinessHours = false
        self.hasBusinessLocation = false
        self.note = (peerView.cachedData as? CachedUserData)?.note.flatMap { note in
            let attr = SettingsHooks.shared.applyMessageEntities([TextEntitiesMessageAttribute(entities: note.entities)], note.text, context, 13, theme.colors.isDark, false).mutableCopy() as! NSMutableAttributedString
            InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: note.entities, isPremium: context.isPremium)

            return Updated_ChatTextInputState(inputText: attr)
        } ?? .init()
    }
    
    public func withUpdatedInited(_ stateInited: Bool) -> EditInfoState {
        return EditInfoState(stateInited: stateInited, firstName: self.firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer: self.peer, peerStatusSettings: self.peerStatusSettings, addToException: self.addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    public func withUpdatedAbout(_ about: String) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: self.lastName, about: about, aboutEdited: true, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer: self.peer, peerStatusSettings: self.peerStatusSettings, addToException: self.addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    
    
    public func withUpdatedFirstName(_ firstName: String) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer: self.peer, peerStatusSettings: self.peerStatusSettings, addToException: self.addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    public func withUpdatedLastName(_ lastName: String) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer: self.peer, peerStatusSettings: self.peerStatusSettings, addToException: self.addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    
    public func withUpdatedPeerView(_ peerView: PeerView) -> EditInfoState {
        let cachedData = peerView.cachedData as? CachedUserData
        let peer = peerView.peers[peerView.peerId] as? TelegramUser
        let about = self.aboutEdited ? self.about : cachedData?.about ?? self.about
        let username = peer?.usernames.first(where: { $0.isActive })?.username
        let peerStatusSettings = cachedData?.peerStatusSettings
        let birthday = cachedData?.birthday
        return EditInfoState(stateInited: true, firstName: stateInited ? self.firstName : peer?.firstName ?? self.firstName, lastName: stateInited ? self.lastName : peer?.lastName ?? self.lastName, about: about, aboutEdited: self.aboutEdited, username: username, phone: peer?.phone, representation: peer?.smallProfileImage, updatingPhotoState: self.updatingPhotoState, peer: peer, peerStatusSettings: peerStatusSettings, addToException: self.addToException, birthday: birthday, personalChannel: self.personalChannel, hasBusinessHours: cachedData?.businessHours != nil, hasBusinessLocation: cachedData?.businessLocation != nil)
    }
    public func withUpdatedUpdatingPhotoState(_ f: (PeerInfoUpdatingPhotoState?) -> PeerInfoUpdatingPhotoState?) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: f(self.updatingPhotoState), peer: self.peer, peerStatusSettings: self.peerStatusSettings, addToException: self.addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    public func withoutUpdatingPhotoState() -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: nil, peer:self.peer, peerStatusSettings: self.peerStatusSettings, addToException: self.addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    public func withUpdatedAddToException(_ addToException: Bool) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer:self.peer, peerStatusSettings: self.peerStatusSettings, addToException: addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    public func withUpdatedPersonalChannel(_ channel: EnginePeer?) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer:self.peer, peerStatusSettings: self.peerStatusSettings, addToException: addToException, birthday: self.birthday, personalChannel: channel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: self.note)
    }
    
    public func withUpdatedNotes(_ note: Updated_ChatTextInputState) -> EditInfoState {
        return EditInfoState(stateInited: self.stateInited, firstName: self.firstName, lastName: self.lastName, about: self.about, aboutEdited: self.aboutEdited, username: self.username, phone: self.phone, representation: self.representation, updatingPhotoState: self.updatingPhotoState, peer: self.peer, peerStatusSettings: self.peerStatusSettings, addToException: addToException, birthday: self.birthday, personalChannel: self.personalChannel, hasBusinessHours: self.hasBusinessHours, hasBusinessLocation: self.hasBusinessLocation, note: note)
    }
    
}

private let _id_info = InputDataIdentifier("_id_info")
private let _id_about = InputDataIdentifier("_id_about")
private let _id_username = InputDataIdentifier("_id_username")
private let _id_phone = InputDataIdentifier("_id_phone")
private let _id_logout = InputDataIdentifier("_id_logout")
private let _id_add_account = InputDataIdentifier("_id_add_account")
private let _id_name_color = InputDataIdentifier("_id_name_color")
private let _id_birthday = InputDataIdentifier("_id_birthday")
private let _id_birthday_remove = InputDataIdentifier("_id_birthday_remove")
private let _id_personal_channel = InputDataIdentifier("_id_personal_channel")
private let _id_chat_automation = InputDataIdentifier("_id_chat_automation")
private let _id_business_hours = InputDataIdentifier("_id_business_hours")
private let _id_business_location = InputDataIdentifier("_id_business_location")

private func editInfoEntries(state: EditInfoState, arguments: EditInfoControllerArguments, activeAccounts: [AccountWithInfo], privacy: AccountPrivacySettings?, updateState:@escaping ((EditInfoState)->EditInfoState)->Void) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_info, equatable: InputDataEquatable(state), comparable: nil, item: { size, stableId -> TableRowItem in
        return EditAccountInfoItem(size, stableId: stableId, account: arguments.context.account, state: state, viewType: .singleItem, updateText: { firstName, lastName in
            updateState { current in
                return current.withUpdatedFirstName(firstName).withUpdatedLastName(lastName).withUpdatedInited(true)
            }
        }, uploadNewPhoto: { control in
            arguments.uploadNewPhoto(control)
        })
    }))
    index += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().editAccountNameDesc), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1

    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().bioHeader), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1

    
    let limit = arguments.context.isPremium ? arguments.context.premiumLimits.about_length_limit_premium : arguments.context.premiumLimits.about_length_limit_default
    
    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.about), error: nil, identifier: _id_about, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().bioPlaceholder, filter: {$0}, limit: Int32(limit)))
    index += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().bioDescription), data: InputDataGeneralTextData(viewType: .textBottomItem)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    let birthdayText: String
    if let birthday = state.birthday {
        birthdayText = birthday.formatted
    } else {
        birthdayText = strings().editAccountBirthdayAdd
    }
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_birthday, data: InputDataGeneralData(name: strings().editAccountBirthdayDate, color: theme.colors.text, icon: nil, type: .context(birthdayText), viewType: state.birthday == nil ? .singleItem : .firstItem, action: arguments.birthday)))
    index += 1
    
    if state.birthday != nil {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_birthday_remove, data: InputDataGeneralData(name: strings().editAccountBirthdayRemove, color: theme.colors.redUI, icon: nil, type: .none, viewType: .lastItem, action: arguments.removeBirthday)))
        index += 1
    }
    
    if let privacy = privacy?.birthday {
        let string: String
        switch privacy {
        case .enableEveryone:
            string = strings().editAccountBirthdayInfoEveryone
        case .enableContacts:
            string = strings().editAccountBirthdayInfoOnlyContacts
        case .disableEveryone:
            string = strings().editAccountBirthdayInfoNobody
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(string, linkHandler: { _ in
            arguments.openBirthdayPrivacy()
        }), data: InputDataGeneralTextData(viewType: .textBottomItem)))
        index += 1
    }
   
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    let username: String
    if let name = state.username {
        username = "@\(name)"
    } else if let name = state.peer?.username {
        username = "@\(name)"
    } else {
        username = ""
    }
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_username, data: InputDataGeneralData(name: strings().editAccountUsername, color: theme.colors.text, icon: nil, type: .nextContext(username), viewType: .firstItem, action: nil)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_phone, data: InputDataGeneralData(name: strings().editAccountChangeNumber, color: theme.colors.text, icon: nil, type: .nextContext(state.phone != nil ? SettingsHooks.shared.formatPhoneNumber(arguments.context, state.phone!) : ""), viewType: .innerItem, action: nil)))
    index += 1
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_name_color, data: InputDataGeneralData(name: strings().appearanceYourNameColor, color: theme.colors.text, type: .imageContext(generateSettingsMenuPeerColorsLabelIcon(peer: state.peer, context: arguments.context), ""), viewType: .innerItem, action: arguments.userNameColor)))
    index += 1
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_personal_channel, data: InputDataGeneralData(name: strings().editAccountPersonalChannel, color: theme.colors.text, type: .nextContext(state.personalChannel?._asPeer().displayTitle ?? strings().editAccountPersonalChannelAdd), viewType: .innerItem, action: arguments.personalChannel)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_chat_automation, data: InputDataGeneralData(name: strings().editAccountInfoChatAutomation, color: theme.colors.text, type: .next, viewType: .lastItem, action: arguments.chatAutomation)))
    index += 1
    
    if state.hasBusinessHours || state.hasBusinessLocation {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        if state.hasBusinessHours {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_business_hours, data: InputDataGeneralData(name: strings().businessHoursTitle, color: theme.colors.text, icon: nil, type: .next, viewType: state.hasBusinessLocation ? .firstItem : .singleItem, action: arguments.openHours)))
        }
        if state.hasBusinessLocation {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_business_location, data: InputDataGeneralData(name: strings().businessLocationTitle, color: theme.colors.text, icon: nil, type: .next, viewType: state.hasBusinessHours ? .lastItem : .singleItem, action: arguments.openLocation)))
        }
    }
    
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    if activeAccounts.count < 3 {
        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_account, data: InputDataGeneralData(name: strings().editAccountAddAccount, color: theme.colors.accent, icon: nil, type: .none, viewType: .firstItem, action: {
            arguments.addAccount()
        })))
        index += 1
    }
   
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_logout, data: InputDataGeneralData(name: strings().editAccountLogout, color: theme.colors.redUI, icon: nil, type: .none, viewType: activeAccounts.count < 3 ? .lastItem : .singleItem, action: nil)))
    index += 1
    
    

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    
    
    return entries
}


public func EditAccountInfoController<Context: AccountContextProtocol>(context: Context, focusOnItemTag: EditSettingsEntryTag? = nil, f: @escaping((ViewController)) -> Void) -> Void {
    
    let state: Promise<EditInfoState> = Promise()
    let stateValue: Atomic<EditInfoState> = Atomic(value: EditInfoState())
    let actionsDisposable = DisposableSet()
    let photoAction = EditAccountPhotoAction()
    let avatarAcquisition = EditAccountAvatarAcquisition()
    let peerDisposable = MetaDisposable()
    let logoutDisposable = MetaDisposable()
    let profileSaveAction = EditAccountProfileSaveAction()
    let birthdaySaveAction = EditAccountProfileSaveAction()
    
    actionsDisposable.add(photoAction)
    actionsDisposable.add(avatarAcquisition)
    actionsDisposable.add(peerDisposable)
    actionsDisposable.add(logoutDisposable)
    let updateState:((EditInfoState)->EditInfoState)->Void = { f in
        state.set(.single(stateValue.modify(f)))
    }
    
    var getController:(()->InputDataController?)? = nil
    
    var peerView:PeerView? = nil
    
    let channel: Signal<EnginePeer?, NoError> = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.PersonalChannel(id: context.peerId)) |> mapToSignal { value in
        switch value {
        case let .known(channel):
            return channel.flatMap {
                context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: $0.peerId))
            } ?? .single(nil)
        case .unknown:
            return .single(nil)
        }
    }
    
    peerDisposable.set(combineLatest(queue: .mainQueue(), context.account.postbox.peerView(id: context.peerId), channel).start(next: { pv, personalChannel in
        peerView = pv
        updateState { current in
            return current.withUpdatedPeerView(pv)
                .withUpdatedPersonalChannel(personalChannel)
        }
    }))
    
    let peerId = context.peerId
    
    
    
    let cancel = { [weak photoAction, weak state, weak stateValue] in
        guard let photoAction, let state, let stateValue, photoAction.cancel() else { return }
        state.set(.single(stateValue.modify { $0.withoutUpdatingPhotoState() }))
    }

    var close:(()->Void)? = nil
    
    let updatePhoto:(Signal<NSImage, NoError>)->Void = { image in
        photoAction.start { isCurrent in
            updateState { $0.withoutUpdatingPhotoState() }
            guard isCurrent() else { return EmptyDisposable }
            let updateSignal = image |> take(1) |> mapToSignal {
                putToTemp(image: $0, compress: true) |> take(1)
            } |> deliverOnMainQueue |> mapToSignal { path -> Signal<URL, NoError> in
                guard isCurrent(), let controller = EditImageModalController(URL(fileURLWithPath: path), context: context, settings: .disableSizes(dimensions: .square, circle: true)) else { return .complete() }
                showModal(with: controller, for: context.window, animationType: .scaleCenter)
                guard isCurrent() else { return .complete() }
                return controller.result |> take(1) |> map { $0.0 }
            } |> map { path -> TelegramMediaResource in
                return LocalFileReferenceMediaResource(localFilePath: path.path, randomId: arc4random64())
            } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
                guard isCurrent() else { return .complete() }
                updateState { state in
                    state.withUpdatedUpdatingPhotoState { _ in
                        PeerInfoUpdatingPhotoState(progress: 0, cancel: cancel)
                    }
                }
                guard isCurrent() else { return .complete() }
                return context.engine.accountData.updateAccountPhoto(resource: EngineMediaResource(resource), videoResource: nil, videoStartTimestamp: nil, markup: nil, mapResourceToAvatarSizes: { resource, representations in
                    return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                })
            } |> deliverOnMainQueue

            return updateSignal.start(next: { status in
                guard isCurrent() else { return }
                updateState { state -> EditInfoState in
                    switch status {
                    case .complete:
                        return state.withoutUpdatingPhotoState()
                    case let .progress(progress):
                        return state.withUpdatedUpdatingPhotoState { current in
                            current?.withUpdatedProgress(progress)
                        }
                    }
                }
            }, error: { _ in
                guard isCurrent() else { return }
                updateState { $0.withoutUpdatingPhotoState() }
            }, completed: {
                guard isCurrent() else { return }
                updateState { $0.withoutUpdatingPhotoState() }
            })
        }
    }

    let updateVideo:(Signal<VideoAvatarGeneratorState, NoError>) -> Void = { signal in
        photoAction.start { isCurrent in
            updateState { $0.withoutUpdatingPhotoState() }
            guard isCurrent() else { return EmptyDisposable }
            let updateSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = signal
            |> deliverOnMainQueue
            |> take(until: { state in
                switch state {
                case .error, .complete:
                    return SignalTakeAction(passthrough: true, complete: true)
                default:
                    return SignalTakeAction(passthrough: true, complete: false)
                }
            })
            |> castError(UploadPeerPhotoError.self)
            |> mapToSignal { state in
                guard isCurrent() else { return .complete() }
                switch state {
                case .error:
                    return .fail(.generic)
                case let .start(path):
                    updateState { state in
                        state.withUpdatedUpdatingPhotoState { _ in
                            PeerInfoUpdatingPhotoState(progress: 0, image: NSImage(contentsOfFile: path)?._cgImage, cancel: cancel)
                        }
                    }
                    return .single(.progress(0))
                case let .progress(value):
                    return .single(.progress(value * 0.2))
                case let .complete(thumb, video, keyFrame):
                    updateState { state in
                        state.withUpdatedUpdatingPhotoState { current in
                            current ?? PeerInfoUpdatingPhotoState(progress: 0.2, image: NSImage(contentsOfFile: thumb)?._cgImage, cancel: cancel)
                        }
                    }
                    guard isCurrent() else { return .complete() }
                    let thumbResource = LocalFileReferenceMediaResource(localFilePath: thumb, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true)
                    let videoResource = LocalFileReferenceMediaResource(localFilePath: video, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true)
                    return context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(thumbResource)), video: context.engine.peers.uploadedPeerVideo(resource: EngineMediaResource(videoResource)) |> map(Optional.init), videoStartTimestamp: keyFrame, mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> map { result in
                        switch result {
                        case let .progress(current):
                            return .progress(0.2 + (current * 0.8))
                        default:
                            return result
                        }
                    }
                }
            } |> deliverOnMainQueue
            return updateSignal.start(next: { status in
                guard isCurrent() else { return }
                updateState { state -> EditInfoState in
                    switch status {
                    case .complete:
                        return state.withoutUpdatingPhotoState()
                    case let .progress(progress):
                        return state.withUpdatedUpdatingPhotoState { current in
                            current?.withUpdatedProgress(progress)
                        }
                    }
                }
            }, error: { _ in
                guard isCurrent() else { return }
                updateState { $0.withoutUpdatingPhotoState() }
            }, completed: {
                guard isCurrent() else { return }
                updateState { $0.withoutUpdatingPhotoState() }
            })
        }
    }

    let makeVideo: (MediaObjectToAvatar) -> Void = { object in
        makeAvatarVideo(object, updatePhoto: updatePhoto, updateVideo: updateVideo)
    }

    let updateBirthday: (TelegramBirthday?) -> Void = { birthday in
        guard let controller = getController?(), let window = controller.view.window as? Window else { return }
        let canPresent: () -> Bool = { [weak controller, weak window] in
            guard let controller, let window else { return false }
            return controller.isLoaded() && controller.view.window === window
        }
        birthdaySaveAction.perform(signal: context.engine.accountData.updateBirthday(birthday: birthday), window: window, canPresent: canPresent, failed: { error in
            switch error {
            case .flood:
                showModalText(for: window, text: strings().loginFloodWait)
            case .generic:
                showModalText(for: window, text: strings().unknownError)
            }
        }, completed: {
            if birthday != nil {
                showModalText(for: window, text: strings().birthdayAlertAdded)
            }
        })
    }

    let arguments = EditInfoControllerArguments(context: context, uploadNewPhoto: { control in
        guard let controller = getController?(), controller.isLoaded(), let window = controller.view.window as? Window, context.window === window else { return }
        let canPresent = avatarAcquisition.presentationCheck { [weak controller, weak window, weak context] in
            guard let controller, let window, let context else { return false }
            return controller.isLoaded() && controller.view.window === window && context.window === window
        }
        var items:[ContextMenuItem] = []
        
        items.append(.init(strings().editAvatarPhotoOrVideo, handler: {
            guard let selected = avatarAcquisition.start(canPresent: canPresent, selected: { (paths: [String]?) in
                if let path = paths?.first, let image = NSImage(contentsOfFile: path) {
                    updatePhoto(.single(image))
                } else if let path = paths?.first {
                    selectVideoAvatar(context: context, path: path, localize: strings().videoAvatarChooseDescProfile, signal: { signal in
                        updateVideo(signal)
                    })
                }
            }) else { return }
            filePanel(with: photoExts + videoExts, allowMultiple: false, canChooseDirectories: false, for: window, completion: selected)
        }, itemImage: MenuAnimation.menu_shared_media.value))
        
        items.append(.init(strings().editAvatarCustomize, handler: {
            guard let selected = avatarAcquisition.start(canPresent: canPresent, selected: makeVideo) else { return }
            showModal(with: AvatarConstructorController(context, target: .avatar, videoSignal: selected), for: window)
        }, itemImage: MenuAnimation.menu_view_sticker_set.value))
        
        if let event = NSApp.currentEvent {
            let menu = ContextMenu()
            for item in items {
                menu.addItem(item)
            }
            let value = AppMenu(menu: menu)
            value.show(event: event, view: control)
        }       
    }, logout: {
        showModal(with: LogoutViewController(context: context, f: f), for: context.window, morphSource: {
            (getController?()?.tableView.item(stableId: InputDataEntryId.general(_id_logout))?.view as? GeneralContainableRowView)?.containerView
        })
    }, username: {
        f(UsernameController(context))
    }, changeNumber: {
        let phoneNumberController = SettingsNavigationHooks.shared.makePhoneNumberIntroController(context)
        let navigation = MajorNavigationController(type(of: phoneNumberController), phoneNumberController, context.window)
        navigation.alwaysAnimate = true
        navigation._frameRect = NSMakeRect(0, 0, 350, 400)
        navigation.readyOnce()
        let phoneRow = getController?()?.tableView.item(stableId: InputDataEntryId.general(_id_phone))?.view as? GeneralContainableRowView
        showModal(with: navigation, for: context.window, morphSource: { [weak phoneRow] in phoneRow?.containerView })
    }, addAccount: {
        let testingEnvironment = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        context.sharedContext.beginNewAuth(testingEnvironment: testingEnvironment)
    }, userNameColor: {
        context.bindings.rootNavigation().push(SettingsHooks.shared.makeSelectColorParentController(context, stateValue.with { $0.peer! }))
    }, birthday: {
        
        guard let controller = getController?() else {
            return
        }
        
        let view = controller.tableView.item(stableId: InputDataEntryId.general(_id_birthday))?.view as? GeneralInteractedRowView
        
        if view?.textView != nil {
            let controller = SettingsNavigationHooks.shared.makeBirthdayCalendarController(context.window, { date in
                updateBirthday(date.birthday)
            })
            
            let nav = NavigationViewController(controller, context.window)

            nav._frameRect = NSMakeRect(0, 0, 300, 310)

            showModal(with: nav, for: context.window, morphSource: { [weak view] in view?.containerView })
        }
    }, openBirthdayPrivacy: {
        let privacySignal = context.privacy |> take(1) |> deliverOnMainQueue
        
        let _ = (privacySignal
            |> deliverOnMainQueue).startStandalone(next: { info in
            if let info = info {
                context.bindings.rootNavigation().push(SelectivePrivacySettingsController(context, kind: .birthday, current: info.birthday, callSettings: nil, phoneDiscoveryEnabled: nil, updated: { updated, updatedCallSettings, _, _ in
                    SettingsHooks.shared.updatePrivacy(context, updated, .birthday)
                }))
            }
        })
    }, removeBirthday: {
        updateBirthday(nil)
    }, personalChannel: {
        showModal(with: SettingsHooks.shared.makePersonalChannelController(context), for: context.window, morphSource: {
            (getController?()?.tableView.item(stableId: InputDataEntryId.general(_id_personal_channel))?.view as? GeneralContainableRowView)?.containerView
        })
    }, openHours: {
        f(SettingsNavigationHooks.shared.makeBusinessHoursController(context))
    }, openLocation: {
        f(SettingsNavigationHooks.shared.makeBusinessLocationController(context))
    }, chatAutomation: {
        f(SettingsNavigationHooks.shared.makeBusinessChatbotController(context))
    })
    
    let controller = InputDataController(dataSignal: combineLatest(state.get() |> deliverOnPrepareQueue, appearanceSignal |> deliverOnPrepareQueue, context.sharedContext.activeAccountsWithInfo, context
        .privacy) |> map {
            editInfoEntries(state: $0.0, arguments: arguments, activeAccounts: $0.2.accounts, privacy: $0.3, updateState: updateState)
    } |> map { InputDataSignalValue(entries: $0) }, title: strings().editAccountTitle, validateData: { data -> InputDataValidation in
        
        if let _ = data[_id_logout] {
            arguments.logout()
            return .fail(.none)
        }
        if let _ = data[_id_username] {
            arguments.username()
            return .fail(.none)
        }
        if let _ = data[_id_phone] {
            arguments.changeNumber()
            return .fail(.none)
        }
        
        if let about = data[_id_about]?.stringValue {
            if context.isPremium {
                
            } else {
                if about.length > context.premiumLimits.about_length_limit_default {
                    SettingsNavigationHooks.shared.showPremiumLimit(context, .caption(about.length))
                    return .fail(.fields([_id_about: .shake]))
                }
            }
        }
        
        return .fail(.doSomething { f in
            guard profileSaveAction.isActive, !profileSaveAction.isPending else { return }
            let current = stateValue.with { $0 }
            if current.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                f(.fail(.fields([_id_info: .shake])))
                return
            }
            guard let peerView, peerView.peers[peerView.peerId] is TelegramUser else { return }
            let updates = valuesRequiringUpdate(state: current, view: peerView)
            if updates.0 == nil, updates.1 == nil {
                close?()
                return
            }
            guard let controller = getController?(), let window = controller.view.window as? Window else { return }
            let canPresent: () -> Bool = { [weak controller, weak window] in
                guard let controller, let window else { return false }
                return controller.isLoaded() && controller.view.window === window
            }
            let signal = context.engine.accountData.updateProfile(firstName: updates.0?.fn, lastName: updates.0?.ln, about: updates.1)
            |> mapError { _ -> EditAccountProfileSaveError in .generic }
            |> ignoreValues
            profileSaveAction.perform(signal: signal, window: window, canPresent: canPresent, failed: { _ in
                f(.fail(.none))
                if canPresent() {
                    showModalText(for: window, text: strings().unknownError)
                }
            }, completed: {
                let latest = stateValue.with { $0 }
                if latest.firstName == current.firstName && latest.lastName == current.lastName && latest.about == current.about {
                    close?()
                }
                _ = showModalSuccess(for: window, icon: theme.icons.successModalProgress, delay: 1.5).start()
            })
        })
    }, updateDatas: { data in
        updateState { current in
            guard let about = data[_id_about]?.stringValue, about != current.about else { return current }
            return current.withUpdatedAbout(about)
        }
        return .fail(.none)
    }, afterDisappear: {
        profileSaveAction.setActive(false)
        birthdaySaveAction.setActive(false)
        actionsDisposable.dispose()
    }, updateDoneValue: { data in
        return { f in
            let current = stateValue.modify {$0}
            if let peerView = peerView {
                _ = valuesRequiringUpdate(state: current, view: peerView)
                f(.enabled(strings().navigationDone))
            } else {
                f(.disabled(strings().navigationDone))
            }
        }
    }, removeAfterDisappear: false, identifier: "account")
    controller.analyticsScreen = .settingsAccount
    
    controller.didLoad = { controller, _ in
        if let focusOnItemTag = focusOnItemTag {
            controller.genericView.tableView.scroll(to: .center(id: focusOnItemTag.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
        }
    }
    
    controller.inputLimitReached = { limit in
        if !context.isPremium {
            SettingsNavigationHooks.shared.showPremiumLimit(context, .about(context.premiumLimits.about_length_limit_default + limit))
        }
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    close = { [weak controller] in
        controller?.navigationController?.back()
    }
    
    controller.willDisappear = { _ in
        avatarAcquisition.setActive(false)
        profileSaveAction.setActive(false)
        birthdaySaveAction.setActive(false)
    }
    controller.willAppear = { _ in
        avatarAcquisition.setActive(true)
        profileSaveAction.setActive(true)
        birthdaySaveAction.setActive(true)
    }
    controller.onDeinit = {
        profileSaveAction.setActive(false)
        birthdaySaveAction.setActive(false)
        actionsDisposable.dispose()
    }

    f(controller)
}
