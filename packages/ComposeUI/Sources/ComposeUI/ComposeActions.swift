import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore

import TGUIKit
import InAppSettings
import Localization
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import AlertsUI
import SelectPeersUI


public func createGroup<Context: AccountContextProtocol>(with context: Context, selectedPeers:Set<PeerId> = Set()) {
    
    let select = { SelectPeersController(titles: ComposeTitles(strings().composeSelectUsers, strings().composeNext), context: context, settings: [.contacts, .remote], isNewGroup: true, selectedPeers: selectedPeers) }
    var analyticsOwner: WeakReference<CreateGroupViewController<Context>>?
    let chooseName = { () -> CreateGroupViewController<Context> in
        let controller = CreateGroupViewController(titles: ComposeTitles(strings().groupNewGroup, strings().composeCreate), context: context)
        analyticsOwner = WeakReference(value: controller)
        return controller
    }
    let signal = execute(context: context, select, chooseName) |> castError(CreateGroupError.self) |> mapToSignal { (_, result) -> Signal<(CreateGroupResult?, String?), CreateGroupError> in
        let signal = showModalProgress(signal: context.engine.peers.createGroup(title: result.title, peerIds: result.peerIds, ttlPeriod: result.autoremoveTimeout) |> map { return ($0, result.picture) }, for: context.window, disposeAfterComplete: false)
        return signal
    } |> mapToSignal{ result, picture -> Signal<(CreateGroupResult?, Bool), CreateGroupError> in
            if let result = result, let picture = picture {
                let resource = LocalFileReferenceMediaResource(localFilePath: picture, randomId: arc4random64())
                let signal:Signal<(CreateGroupResult?, Bool), NoError> = context.engine.peers.updatePeerPhoto(peerId: result.peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(resource)), mapResourceToAvatarSizes: { resource, representations in
                    return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                }) |> `catch` {_ in .complete()} |> map { value in
                    switch value {
                    case .complete:
                        return (result, false)
                    default:
                        return (nil, false)
                    }
                }
                
                return .single((result, true)) |> then(signal |> castError(CreateGroupError.self))
            }
        return .single((result, true))
        } |> deliverOnMainQueue |> filter {$0.1}
    
    
    _ = signal.start(next: { result, complete in
        if let result = result, complete {
            analyticsOwner?.value?.analyticsDidCreate()
            ComposeUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(result.peerId))
        }
    }, error: { error in
        let text: String
        switch error {
        case .privacy:
            text = strings().privacyGroupsAndChannelsInviteToChannelMultipleError
        case .generic:
            text = strings().unknownError
        case .restricted:
            text = strings().unknownError
        case .tooMuchLocationBasedGroups:
            text = strings().unknownError
        case let .serverProvided(error):
            text = error
        case .tooMuchJoined:
            text = strings().channelErrorAddTooMuch
        }
        alert(for: context.window, info: text)
    })
}


public func createGroupDirectly<Context: AccountContextProtocol>(with context: Context, selectedPeers: [PeerId] = [], requires: CreateGroupRequires = [], onCreate:@escaping(PeerId)->Void = { _ in })  {
    let chooseName = CreateGroupViewController(titles: ComposeTitles(strings().groupNewGroup, strings().composeCreate), context: context, requires: requires)
    let analyticsOwner = WeakReference(value: chooseName)
    let signal = completion(of: chooseName.onComplete, until: chooseName) |> mapToSignal { result -> Signal<(CreateGroupResult?, Bool), NoError> in
        
        let signal: Signal<CreateGroupResult?, CreateGroupError>
        if requires.isEmpty {
            signal = context.engine.peers.createGroup(title: result.title, peerIds: result.peerIds, ttlPeriod: result.autoremoveTimeout)
        } else {
            signal = context.engine.peers.createSupergroup(title: result.title, description: nil, username: result.username, isForum: result.isForum) |> map {
                return .init(peerId: $0, result: .init(forbiddenPeers: []))
            } |> mapError { error -> CreateGroupError in
                switch error {
                case .generic:
                    return .generic
                case .restricted:
                    return .restricted
                case .tooMuchJoined:
                    return .tooMuchJoined
                case .tooMuchLocationBasedGroups:
                    return .tooMuchLocationBasedGroups
                case let .serverProvided(value):
                    return .serverProvided(value)
                }
            }
        }
        
        
        let createSignal = showModalProgress(signal: signal |> map { return ($0, result.picture ) }, for: context.window, disposeAfterComplete: false)

        return createSignal
         |> `catch` { _ in
            return .single((nil, nil))
         }
         |> mapToSignal { groupResult, picture -> Signal<(CreateGroupResult?, Bool), NoError> in
            if let groupResult = groupResult {
                
                var additionalSignals:[Signal<Void, NoError>] = []
                
                if let picture = picture {
                    let resource = LocalFileReferenceMediaResource(localFilePath: picture, randomId: arc4random64())
                    let signal:Signal<Void, NoError> = context.engine.peers.updatePeerPhoto(peerId: groupResult.peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(resource)), mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> `catch` { _ in .complete() } |> map { _ in }
                    additionalSignals.append(signal)
                }
                
                if !requires.isEmpty {
                    if let username = result.username {
                        additionalSignals.append(context.engine.peers.updateAddressName(domain: .peer(groupResult.peerId), name: username) |> `catch` { _ in .complete() })
                    }
                    additionalSignals.append(context.peerChannelMemberCategoriesContextsManager.addMembersAllowPartial(peerId: groupResult.peerId, memberIds: result.peerIds) |> map { _ in })
                }
                
                let combined:Signal<(CreateGroupResult?, Bool), NoError> = combineLatest(additionalSignals) |> map { _ in (nil, false) }
                
                return .single((groupResult, true)) |> then(combined)
            }
             return .single((groupResult, true))
        } |> deliverOnMainQueue
        
    }
    
    context.bindings.rootNavigation().push(chooseName)
    chooseName.restart(with: ComposeState(selectedPeers))
    _ = signal.start(next: { result, complete in
        if let result = result, complete {
            analyticsOwner.value?.analyticsDidCreate()
            ComposeUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(result.peerId))
            onCreate(result.peerId)
            
        }
    })
}

public func createSupergroup<Context: AccountContextProtocol>(with context: Context, defaultText: String = "") -> Signal<PeerId?, NoError> {
    let chooseName = CreateGroupViewController(titles: ComposeTitles(strings().groupNewGroup, strings().composeCreate), context: context, defaultText: defaultText)
    let analyticsOwner = WeakReference(value: chooseName)
    context.bindings.rootNavigation().push(chooseName)
    chooseName.restart(with: ComposeState([]))
    let signal = chooseName.onComplete.get() |> mapToSignal { result -> Signal<(PeerId?, Bool), NoError> in
        
        let createSignal: Signal<(PeerId?, String?), CreateChannelError> = showModalProgress(signal: context.engine.peers.createSupergroup(title: result.title, description: nil) |> map { return ($0, result.picture) }, for: context.window, disposeAfterComplete: false)
        
        return createSignal
         |> `catch` { _ in
            return .single((nil, nil))
         }
         |> mapToSignal { peerId, picture -> Signal<(PeerId?, Bool), NoError> in
            if let peerId = peerId {
                analyticsOwner.value?.analyticsDidCreate()
                var additionalSignals:[Signal<Void, NoError>] = []
                
                if let picture = picture {
                    let resource = LocalFileReferenceMediaResource(localFilePath: picture, randomId: arc4random64())
                    let signal:Signal<Void, NoError> = context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(resource)), mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> `catch` { _ in .complete() } |> map { _ in }
                    additionalSignals.append(signal)
                }
                
                let combined:Signal<(PeerId?, Bool), NoError> = combineLatest(additionalSignals) |> map { _ in (nil, false) }
                
                
                
                return .single((peerId, true)) |> then(combined)
            }
            return .single((peerId, true))
        } |> deliverOnMainQueue
    }
    
    return signal |> filter { $0.1 } |> map { $0.0 }
}

public func createChannel<Context: AccountContextProtocol>(with context: Context) {
    
    let intro = ChannelIntroViewController(context)
    if FastSettings.needShowChannelIntro {
        context.bindings.rootNavigation().push(intro)
    }
    
    let introCompletion: Signal<Void, NoError> = FastSettings.needShowChannelIntro ? completion(of: intro.onComplete, until: intro) : Signal<Void, NoError>.single(Void())
    
    let promise: Promise<PeerId?> = Promise()
    let closedBeforeCreate = DisposableSet()
    var channelCreated = false
    
    let create = introCompletion |> mapToSignal { () -> Signal<PeerId?, NoError> in
        let create = CreateChannelController(context: context, onComplete: { peerId, completed in
            channelCreated = true
            FastSettings.markChannelIntroHasSeen()
            context.bindings.rootNavigation().removeAll()
            
            var chat: ViewController? = ComposeUIHooks.shared.makeChatController(context, peerId)
            var visibility: ComposeChannelVisibilityController? = ComposeUIHooks.shared.makeChannelVisibilityController(context, peerId, true, true)

            chat!.navigationController = context.bindings.rootNavigation()
            visibility!.navigationController = context.bindings.rootNavigation()
            
            chat!.loadViewIfNeeded(context.bindings.rootNavigation().bounds)
            visibility!.loadViewIfNeeded(context.bindings.rootNavigation().bounds)
            
            
            
            let chatSignal = chat!.ready.get() |> filter { $0 } |> take(1) |> ignoreValues
            let visibilitySignal = visibility!.ready.get() |> filter { $0 } |> take(1) |> ignoreValues

            _ = combineLatest(queue: .mainQueue(), chatSignal, visibilitySignal).start(completed: {
                context.bindings.rootNavigation().push(chat!)
                context.bindings.rootNavigation().push(visibility!)

                chat = nil
                visibility = nil
            })
           
            promise.set(visibility!.onComplete.get() |> map { _ in return peerId })
        })
        let createDeinit = create.onDeinit
        create.onDeinit = {
            createDeinit?()
            if !channelCreated {
                closedBeforeCreate.dispose()
            }
        }
        context.bindings.rootNavigation().push(create)
        let result = promise.get() |> take(1)
        return Signal { subscriber in
            let disposable = result.start(next: { peerId in
                subscriber.putNext(peerId)
            }, completed: {
                subscriber.putCompletion()
            })
            closedBeforeCreate.add(ActionDisposable {
                disposable.dispose()
                subscriber.putCompletion()
            })
            return disposable
        }
    }
    
    _ = create.start(next: { peerId in
        if let peerId = peerId {
            ComposeUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(peerId))
        } else {
            context.bindings.rootNavigation().close()
        }
    })
}


private func completion<T>(of promise: Promise<T>, until controller: ViewController) -> Signal<T, NoError> {
    let signal = promise.get()
    return Signal { [weak controller] subscriber in
        let disposable = signal.start(next: { value in
            subscriber.putNext(value)
        })
        controller?.onDeinit = {
            disposable.dispose()
            subscriber.putCompletion()
        }
        return disposable
    }
}

private func execute<T1, I1, T2, V1, V2, Context: AccountContextProtocol>(context: Context, _ c1: @escaping() -> SelectPeersMainController<T1,I1,V1>, _ c2: @escaping() -> EmptyComposeController<T1, T2, V2, Context>) -> Signal<(T1,T2), NoError> {
    
    let c1Controller = c1()
    context.bindings.rootNavigation().push(c1Controller)
    return completion(of: c1Controller.onComplete, until: c1Controller) |> mapToSignal {  (c1Next) -> Signal<(T1,T2), NoError> in
        let c2Controller = c2()
        context.bindings.rootNavigation().push(c2Controller)
        c2Controller.restart(with: ComposeState(c1Next))
        return completion(of: c2Controller.onComplete, until: c2Controller) |> mapToSignal{ (c2Next) -> Signal<(T1,T2), NoError> in
            return .single((c1Next,c2Next))
        }
    }
}

private func push<I,O,V,Context: AccountContextProtocol>(context: Context, controller:EmptyComposeController<I,O,V,Context>) -> Signal<O, NoError> {
    context.bindings.rootNavigation().push(controller)
    return controller.onComplete.get()
}

private func push<I,O,V,Context: AccountContextProtocol>(context: Context, controller:EmptyComposeController<I,O,V,Context>, input:I) -> Signal<O, NoError> {
    context.bindings.rootNavigation().push(controller)
    controller.restart(with: ComposeState(input))
    return controller.onComplete.get()
}

private func execute<T1, I1, T2, T3, V1, V2, V3, Context: AccountContextProtocol>(context: Context, _ c1: @escaping () -> EmptyComposeController<I1,T1,V1,Context>, _ c2: @escaping() -> EmptyComposeController<T1, T2, V2, Context>, _ c3: @escaping() -> EmptyComposeController<T2, T3, V3, Context>) -> Signal<T3, NoError> {
    
    return push(context: context, controller: c1()) |> mapToSignal { (c1Next) -> Signal<T3, NoError> in
        return push(context: context, controller: c2(), input:c1Next) |> mapToSignal{ (c2Next) -> Signal<T3, NoError> in
            return push(context: context, controller: c3(), input:c2Next) |> mapToSignal{ (c3Next) -> Signal<T3, NoError> in
                return .single(c3Next)
            }
        }
    }
}
