import Cocoa
import TLottie

extension TLottieBridge: @retroactive LottieFrameRenderer {}

func installLottieRenderHooks() {
    LottieRenderHooks.install(LottieRenderHooks(makeRenderer: { json in
        return TLottieBridge(json: json)
    }))
}
