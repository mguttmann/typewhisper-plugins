import Foundation

public enum RefreshThreshold: Sendable {
    /// Used by the 60s background tick — keeps tokens warm well before expiry.
    case scheduler
    /// Used by `activate()` and `process()` — refreshes only if we're about to be unusable.
    case immediate

    var seconds: TimeInterval {
        switch self {
        case .scheduler: return 15 * 60
        case .immediate: return 5 * 60
        }
    }
}

public enum RefreshScheduler {
    public static let tickInterval: TimeInterval = 60

    public static func needsRefresh(tokens: TokenSet, threshold: RefreshThreshold, now: Date = Date()) -> Bool {
        tokens.expiresAt.timeIntervalSince(now) < threshold.seconds
    }
}

/// Background-tick wrapper around a `Timer`. Used by the plugin's lifecycle; not unit-tested
/// directly because `Timer` is hard to fake without `XCTest`. The decision logic above is
/// the part with real branches and is fully tested.
public final class RefreshTimer: @unchecked Sendable {
    private var timer: Timer?
    private let onTick: @Sendable () -> Void

    public init(onTick: @Sendable @escaping () -> Void) {
        self.onTick = onTick
    }

    public func start() {
        stop()
        let t = Timer(timeInterval: RefreshScheduler.tickInterval, repeats: true) { [onTick] _ in
            onTick()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
