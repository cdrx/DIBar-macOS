import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.dibar", category: "SleepTimer")

/// Session-only sleep timer; never persisted across launches. Fires `onFire`
/// once when the deadline passes, then goes quiet.
@Observable
@MainActor
final class SleepTimer {
    nonisolated static let maximumMinutes = 720.0

    private(set) var endDate: Date?
    private var timer: Timer?

    /// What to do when the timer fires (pause playback, maybe quit).
    var onFire: (() -> Void)?

    func start(minutes: Double) {
        guard minutes.isFinite, minutes > 0 else { return }
        let clamped = min(minutes, Self.maximumMinutes)
        endDate = Date().addingTimeInterval(clamped * 60)
        // A 1s date-compare timer instead of a one-shot: after system sleep the
        // next tick still fires an overdue timer correctly.
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            timer?.tolerance = 0.3
        }
        log.info("sleep timer: set for \(clamped)min")
    }

    func cancel() {
        endDate = nil
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let end = endDate, Date() >= end else { return }
        cancel()
        log.info("sleep timer: fired")
        onFire?()
    }
}

enum SleepTimerInput {
    static func sanitized(_ input: String) -> String {
        var result = ""
        var hasPeriod = false
        for character in input {
            if character >= "0", character <= "9" {
                result.append(character)
            } else if character == ".", !hasPeriod {
                hasPeriod = true
                result.append(character)
            }
        }
        return result
    }

    static func minutes(from input: String) -> Double? {
        guard let value = Double(input), value.isFinite, value > 0 else { return nil }
        return value
    }

    static func effectiveMinutes(from input: String) -> Double? {
        guard let value = minutes(from: input) else { return nil }
        return min(value, SleepTimer.maximumMinutes)
    }

    static func storedValue(for minutes: Double) -> String {
        minutes.rounded() == minutes ? String(Int(minutes)) : String(minutes)
    }
}
