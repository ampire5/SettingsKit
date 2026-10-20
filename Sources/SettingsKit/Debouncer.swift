import Foundation

/// Coalesces a burst of values (a colour well dragged in the colour panel) into one commit after a pause.
/// The last submitted value wins; `flush()` commits a pending value at once (the view goes away); `cancel()`
/// drops it. The clock is injectable: `schedule` runs the action after the delay and returns its canceller.
@MainActor
final class Debouncer<Value> {
    typealias Schedule = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> @MainActor () -> Void

    /// Waits on the main actor with `Task.sleep`.
    static var taskSchedule: Schedule {
        { delay, action in
            let task = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                if !Task.isCancelled { action() }
            }
            return { task.cancel() }
        }
    }

    private let delay: TimeInterval
    private let schedule: Schedule
    private var cancelTimer: (@MainActor () -> Void)?
    private var commit: (@MainActor (Value) -> Void)?
    /// The value that waits for the pause.
    private(set) var pending: Value?

    init(delay: TimeInterval = 0.25, schedule: Schedule? = nil) {
        self.delay = delay
        self.schedule = schedule ?? Self.taskSchedule
    }

    /// Replaces the pending value and restarts the pause.
    func submit(_ value: Value, commit: @escaping @MainActor (Value) -> Void) {
        cancelTimer?()
        pending = value
        self.commit = commit
        cancelTimer = schedule(delay) { [weak self] in self?.flush() }
    }

    /// Commits the pending value now, if there is one.
    func flush() {
        cancelTimer?()
        cancelTimer = nil
        guard let value = pending, let commit else { return }
        pending = nil
        self.commit = nil
        commit(value)
    }

    func cancel() {
        cancelTimer?()
        cancelTimer = nil
        pending = nil
        commit = nil
    }
}
