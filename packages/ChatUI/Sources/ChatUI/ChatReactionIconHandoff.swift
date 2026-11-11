final class ChatReactionIconHandoff {
    private let hide: () -> Void
    private let show: () -> Void
    private var finished = false
    private var hidden = false

    init(hide: @escaping () -> Void, show: @escaping () -> Void) {
        self.hide = hide
        self.show = show
    }

    func contentDidDraw() {
        guard !finished, !hidden else { return }
        hidden = true
        hide()
    }

    func finish() {
        guard !finished else { return }
        finished = true
        if hidden { hidden = false; show() }
    }
}
