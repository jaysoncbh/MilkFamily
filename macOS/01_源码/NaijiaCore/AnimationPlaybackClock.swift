import Foundation

/// Time belongs to this playback, rather than the system's absolute reference epoch.
public struct AnimationPlaybackClock: Sendable {
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date?
    public init() {}

    public func elapsed(at date: Date) -> TimeInterval {
        accumulated + (resumedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    public mutating func setPlaying(_ playing: Bool, at date: Date) {
        if playing {
            if resumedAt == nil { resumedAt = date }
        } else if resumedAt != nil {
            accumulated = elapsed(at: date)
            resumedAt = nil
        }
    }
}
