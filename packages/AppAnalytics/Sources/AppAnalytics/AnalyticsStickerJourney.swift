import Foundation

public enum AnalyticsStickerSubmissionResult {
    case accepted
    case retryableFailure(AnalyticsFlows.StickersEdit.LastBlocker)
    case terminalFailure(AnalyticsFlows.StickersEdit.LastBlocker)
}

public final class AnalyticsStickerJourney: AnalyticsRevocable {
    public typealias Spec = AnalyticsFlows.StickersEdit

    private enum Stage {
        case acquiringImage
        case acquiringSticker
        case preparing
        case editing
        case ready
        case naming
        case preparingSend
        case submitting
    }

    private let scope: AnalyticsScope?
    private var flow: AnalyticsFlow<Spec>?
    private var entry: Spec.EntryPoint?
    private var stage: Stage?
    private var destination: Spec.Destination?
    private var retryPending = false
    private var retryCount = 0
    private var attempt = 0

    public init(context: AnalyticsContext, entry: Spec.EntryPoint, via: AnalyticsValues.Via? = nil, source: AnalyticsScreen? = nil) {
        scope = source?.isAnalyticsExcluded == true ? nil : context.scope
        scope?.perform {
            guard let analytics = context.analytics, !context.isExcluded else { return }
            let flow = AnalyticsFlow<Spec>(analytics: analytics, scope: scope, source: source)
            flow.set(entryPoint: entry)
            flow.set(via: via)
            flow.set(retryCount: ._0)
            flow.step(.attempt)
            guard scope?.isValid == true else { return }
            self.flow = flow
            self.entry = entry
            scope?.observe(self)
            switch entry {
            case .composerCreate:
                stage = .acquiringImage
                flow.step(.openImagePicker)
            case .packAddImage:
                destination = .existingPack
                stage = .acquiringImage
                flow.step(.openImagePicker)
            case .packAddExisting:
                destination = .existingPack
                stage = .acquiringSticker
                flow.step(.openStickerPicker)
            case .packReplace:
                destination = .replacement
                stage = .acquiringImage
                flow.step(.openImagePicker)
            case .packRename:
                destination = .rename
                stage = .naming
                flow.step(.openName)
            }
            flow.set(destination: destination)
        }
    }

    public func imageSelected() {
        scope?.perform {
            guard stage == .acquiringImage else { return }
            stage = .preparing
            flow?.step(.imageSelected)
        }
    }

    public func editorShown() {
        scope?.perform {
            guard stage == .preparing || (stage == .ready && entry != .packAddExisting && entry != .packRename) else { return }
            stage = .editing
            flow?.step(.openEditor)
        }
    }

    public func editorApplied(mode: Spec.ImageMode) {
        scope?.perform {
            guard stage == .editing || (stage == .ready && entry != .packAddExisting && entry != .packRename) else { return }
            stage = .ready
            flow?.set(imageMode: mode)
            flow?.step(.applyEditor)
        }
    }

    public func preparedWithoutEditor() {
        scope?.perform {
            guard stage == .preparing else { return }
            stage = .ready
            flow?.set(imageMode: .wholeImage)
            flow?.step(.prepared)
        }
    }

    public func existingStickerSelected() {
        scope?.perform {
            guard stage == .acquiringSticker else { return }
            stage = .ready
            flow?.step(.stickerSelected)
        }
    }

    public func chooseDestination(_ destination: Spec.Destination) {
        scope?.perform {
            guard stage == .ready, entry == .composerCreate else { return }
            switch destination {
            case .send, .favorites, .newPack, .existingPack:
                break
            case .replacement, .rename:
                return
            }
            if self.destination != destination {
                self.destination = destination
                flow?.set(destination: destination)
                flow?.step(.chooseDestination)
            }
            guard scope?.isValid == true, stage == .ready else { return }
            if destination == .newPack {
                stage = .naming
                flow?.step(.openName)
            }
        }
    }

    public func nameAccepted() {
        scope?.perform {
            guard stage == .naming else { return }
            stage = .ready
            flow?.step(.acceptName)
        }
    }

    public func cancelNaming() {
        scope?.perform {
            guard stage == .naming else { return }
            if entry == .packRename {
                cancel()
            } else {
                stage = .ready
                destination = nil
                flow?.set(destination: nil)
                flow?.step(.cancelName)
            }
        }
    }

    public func blocked(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage != nil, stage != .submitting else { return }
            flow?.set(lastBlocker: reason)
            flow?.step(.blocked)
        }
    }

    public func fail(_ reason: Spec.LastBlocker) {
        scope?.perform {
            guard stage != nil, stage != .submitting else { return }
            blocked(reason)
            finish(.fail)
        }
    }

    public func prepareSend() -> AnalyticsStickerSendRequest? {
        return scope?.perform {
            guard stage == .ready, destination == .send else { return nil }
            guard attempt < 256 else {
                discard()
                return nil
            }
            stage = .preparingSend
            flow?.step(.prepareSend)
            guard stage == .preparingSend, scope?.isValid == true else { return nil }
            return AnalyticsStickerSendRequest(journey: self, attempt: attempt + 1)
        } ?? nil
    }

    fileprivate func sendStep(_ step: Spec.Step, attempt: Int) {
        scope?.perform {
            guard stage == .preparingSend, self.attempt + 1 == attempt else { return }
            switch step {
            case .openSchedule, .cancelSchedule, .openConfirmation, .cancelConfirmation:
                flow?.step(step)
            default:
                break
            }
        }
    }

    fileprivate func commitSend(attempt: Int, scheduled: Bool, silent: Bool) -> AnalyticsStickerSubmission? {
        return scope?.perform {
            guard stage == .preparingSend, self.attempt + 1 == attempt else { return nil }
            flow?.set(scheduled: scheduled)
            flow?.set(silent: silent)
            return beginSubmission(from: .preparingSend)
        } ?? nil
    }

    fileprivate func cancelSend(attempt: Int) {
        scope?.perform {
            guard stage == .preparingSend, self.attempt + 1 == attempt else { return }
            cancel()
        }
    }

    fileprivate func failSend(_ reason: Spec.LastBlocker, attempt: Int) {
        scope?.perform {
            guard stage == .preparingSend, self.attempt + 1 == attempt else { return }
            fail(reason)
        }
    }

    fileprivate func restrictSend(to context: AnalyticsContext, attempt: Int) {
        scope?.policy.sync {
            guard (stage == .preparingSend && self.attempt + 1 == attempt) || (stage == .submitting && self.attempt == attempt) else { return }
            if context.scope !== scope || context.isExcluded { discard() }
        }
    }

    fileprivate func endSend(attempt: Int) {
        scope?.policy.sync {
            guard stage == .preparingSend, self.attempt + 1 == attempt else { return }
            discard()
        }
    }

    public func beginSubmission() -> AnalyticsStickerSubmission? {
        return scope?.perform {
            guard destination != .send else { return nil }
            return beginSubmission(from: .ready)
        } ?? nil
    }

    private func beginSubmission(from expectedStage: Stage) -> AnalyticsStickerSubmission? {
        return scope?.perform {
            guard stage == expectedStage, destination != nil else { return nil }
            guard attempt < 256 else {
                discard()
                return nil
            }
            attempt += 1
            stage = .submitting
            if retryPending {
                retryPending = false
                retryCount = min(retryCount + 1, 4)
                flow?.set(retryCount: retryCount == 1 ? ._1 : retryCount < 4 ? ._2_3 : ._4_plus)
                flow?.step(.retry)
            }
            flow?.step(.submit)
            guard stage == .submitting, scope?.isValid == true else { return nil }
            return AnalyticsStickerSubmission(journey: self, attempt: attempt)
        } ?? nil
    }

    fileprivate func resolve(attempt: Int, buildResult: () -> AnalyticsStickerSubmissionResult?) {
        scope?.perform {
            guard stage == .submitting, self.attempt == attempt else { return }
            let result = buildResult()
            guard stage == .submitting, self.attempt == attempt, scope?.isValid == true else { return }
            switch result {
            case .accepted?:
                flow?.step(.accepted)
                finish(.success)
            case let .retryableFailure(reason)?:
                stage = .ready
                retryPending = true
                flow?.set(lastBlocker: reason)
                flow?.step(.rejected)
            case let .terminalFailure(reason)?:
                flow?.set(lastBlocker: reason)
                flow?.step(.rejected)
                finish(.fail)
            case nil:
                discard()
            }
        }
    }

    fileprivate func end(attempt: Int) {
        scope?.policy.sync {
            guard stage == .submitting, self.attempt == attempt else { return }
            discard()
        }
    }

    public func cancel() {
        scope?.perform {
            guard stage != nil, stage != .submitting else { return }
            flow?.step(.cancel)
            finish(.cancelled)
        }
    }

    public func endInteraction() {
        scope?.policy.sync {
            guard stage != .submitting, stage != .preparingSend else { return }
            discard()
        }
    }

    public func endEditor() {
        scope?.policy.sync {
            guard stage != .naming else { return }
            endInteraction()
        }
    }

    private func finish(_ outcome: AnalyticsFlowOutcome) {
        let flow = self.flow
        self.flow = nil
        revokeAnalytics()
        scope?.removeObserver(self)
        flow?.finish(outcome)
    }

    public func discard() {
        scope?.policy.sync {
            revokeAnalytics()
            scope?.removeObserver(self)
        }
    }

    func revokeAnalytics() {
        flow?.discard()
        flow = nil
        entry = nil
        stage = nil
        destination = nil
        retryPending = false
        retryCount = 0
        attempt = 0
    }

    var retainedStateCount: Int {
        return scope?.policy.sync { () -> Int in
            var count: Int = flow?.storedStepCount ?? 0
            if entry != nil {
                count += 1
            }
            if stage != nil {
                count += 1
            }
            if destination != nil {
                count += 1
            }
            if retryPending {
                count += 1
            }
            if retryCount != 0 {
                count += 1
            }
            if attempt != 0 {
                count += 1
            }
            return count
        } ?? 0
    }

    deinit {
        discard()
    }
}

public final class AnalyticsStickerSubmission {
    private let journey: AnalyticsStickerJourney
    private let attempt: Int

    fileprivate init(journey: AnalyticsStickerJourney, attempt: Int) {
        self.journey = journey
        self.attempt = attempt
    }

    public func complete(buildResult: () -> AnalyticsStickerSubmissionResult?) {
        journey.resolve(attempt: attempt, buildResult: buildResult)
    }

    public func end() {
        journey.end(attempt: attempt)
    }

    deinit {
        end()
    }
}

public final class AnalyticsStickerSendRequest {
    private let journey: AnalyticsStickerJourney
    private let attempt: Int

    fileprivate init(journey: AnalyticsStickerJourney, attempt: Int) {
        self.journey = journey
        self.attempt = attempt
    }

    public func restrict(to context: AnalyticsContext) {
        journey.restrictSend(to: context, attempt: attempt)
    }

    public func step(_ step: AnalyticsStickerJourney.Spec.Step) {
        journey.sendStep(step, attempt: attempt)
    }

    public func commit(scheduled: Bool, silent: Bool) -> AnalyticsStickerSubmission? {
        return journey.commitSend(attempt: attempt, scheduled: scheduled, silent: silent)
    }

    public func cancel() {
        journey.cancelSend(attempt: attempt)
    }

    public func fail(_ reason: AnalyticsStickerJourney.Spec.LastBlocker) {
        journey.failSend(reason, attempt: attempt)
    }

    public func end() {
        journey.endSend(attempt: attempt)
    }

    deinit {
        end()
    }
}
