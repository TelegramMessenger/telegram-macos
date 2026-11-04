import Cocoa

public final class GlassContainerView: FlippableView {

    public let glassContainer: NSView & GlassEffectContainer
    public let glassContent: GlassContentView
    private(set) public var ghosts: [LiquidGlassView] = []
    private let mergesGhosts: Bool
    private var validLayout: NSSize?
    private var deferredUnflippedLayout: NSSize?
    private var deferredUnflippedLayoutToken: UInt = 0

    public init(frame frameRect: NSRect, flipped: Bool = true, spacing: CGFloat = 5) {
        let container = makeGlassEffectContainer(frame: frameRect, flipped: flipped, spacing: spacing)
        container.wantsLayer = true
        container.layer?.masksToBounds = false

        let content = GlassContentView(frame: NSRect(origin: .zero, size: frameRect.size))
        content.layer?.masksToBounds = false
        container.contentView = content

        self.glassContainer = container
        self.glassContent = content
        self.mergesGhosts = !(container is LegacyGlassEffectContainerView)

        super.init(frame: frameRect)

        self.flip = flipped
        content.flip = flipped

        self.layer?.masksToBounds = false
        addSubview(container)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public required init(frame frameRect: NSRect) { fatalError("use init(frame:flipped:spacing:)") }

    public func addGhost(_ ghost: LiquidGlassView) {
        ghosts.append(ghost)
        glassContent.addSubview(ghost)
        if mergesGhosts {
            ghost.effectView.removeFromSuperview()
            glassContent.addSubview(ghost.effectView)
            ghost.effectView.frame = ghost.frame
        }
        ghost.validGhostFrame = nil
    }

    public func removeGhost(_ ghost: LiquidGlassView) {
        ghosts.removeAll { $0 === ghost }
        if mergesGhosts {
            ghost.effectView.removeFromSuperview()
        }
        ghost.removeFromSuperview()
        ghost.validGhostFrame = nil
    }

    public func setGhostFrame(_ ghost: LiquidGlassView, frame: NSRect, transition: ContainedViewLayoutTransition) {
        if ghost.validGhostFrame == frame {
            ghost.updateCornerRadius(size: frame.size)
            return
        }
        ghost.validGhostFrame = frame
        if mergesGhosts {
            switch transition {
            case .immediate:
                ghost.frame = frame
                ghost.effectView.frame = frame
            case let .animated(duration, curve):
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = duration
                    if curve.timingFunction == .spring {
                        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0)
                    } else {
                        context.timingFunction = CAMediaTimingFunction(name: curve.timingFunction)
                    }
                    context.allowsImplicitAnimation = true
                    ghost.setAnimatorFrame(frame)
                    ghost.effectView.animator().frame = frame
                })
            }
        } else {
            transition.updateFrame(view: ghost, frame: frame)
            ghost.updateLayout(size: frame.size, transition: transition)
        }
        if !transition.isAnimated {
            ghost.updateLayout(size: frame.size, transition: .immediate)
        }
    }

    private func applyHostLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let rect = NSRect(origin: .zero, size: size)
        let containerTransition: ContainedViewLayoutTransition = self.flip ? transition : .immediate
        containerTransition.updateFrame(view: self, frame: NSRect(origin: frame.origin, size: size))
        containerTransition.updateFrame(view: glassContainer, frame: rect)
        containerTransition.updateFrame(view: glassContent, frame: rect)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if size == validLayout { return }
        validLayout = size

        let hasOverflowingGlass = ghosts.contains { $0.frame.maxY > size.height }
        guard mergesGhosts, transition.isAnimated, !self.flip || hasOverflowingGlass else {
            deferredUnflippedLayout = nil
            deferredUnflippedLayoutToken &+= 1
            applyHostLayout(size: size, transition: transition)
            return
        }

        let retainedHeight = max(frame.height, glassContainer.frame.height, glassContent.frame.height)
        guard size.height < retainedHeight else {
            deferredUnflippedLayout = nil
            deferredUnflippedLayoutToken &+= 1
            applyHostLayout(size: size, transition: .immediate)
            return
        }

        let retainedSize = NSSize(width: size.width, height: retainedHeight)
        applyHostLayout(size: retainedSize, transition: .immediate)

        deferredUnflippedLayout = size
        deferredUnflippedLayoutToken &+= 1
        let token = deferredUnflippedLayoutToken
        let duration = transition.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            guard self.deferredUnflippedLayoutToken == token,
                  let deferredSize = self.deferredUnflippedLayout else {
                return
            }
            self.deferredUnflippedLayout = nil
            self.applyHostLayout(size: deferredSize, transition: .immediate)
        }
    }
}
