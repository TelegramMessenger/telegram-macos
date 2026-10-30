import Foundation

func performRecordingDismissal(timeout: TimeInterval, animations: (@escaping () -> Void) -> Void, completion: @escaping () -> Void) {
    var completed = false
    let finish = {
        guard !completed else { return }
        completed = true
        completion()
    }
    animations(finish)
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
}
