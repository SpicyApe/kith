// MidnightTimer.swift — flips "today" without a relaunch.

import Foundation
import KithCore

@MainActor
final class MidnightTimer {
    private var task: Task<Void, Never>?
    private var handler: (() -> Void)?
    private var timeZone: String = TimeZone.current.identifier

    func start(tz: String, onFire: @escaping () -> Void) {
        self.timeZone = tz
        self.handler = onFire
        schedule()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Call on foreground: the device may have slept through midnight.
    func reschedule(tz: String) {
        self.timeZone = tz
        schedule()
    }

    private func schedule() {
        task?.cancel()
        let seconds = max(1, LocalDay.secondsUntilMidnight(Date(), tz: timeZone))
        // Half a second past midnight so `LocalDay.date` has definitely rolled over.
        let nanoseconds = UInt64(seconds) * 1_000_000_000 + 500_000_000
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.handler?()
            self.schedule()
        }
    }
}
