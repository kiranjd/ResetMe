import Foundation

public struct IndicatorVisibility {
    public static func shouldShow(alwaysOn: Bool, hovered: Bool, expanded: Bool, recentChange: Bool, activeAppSelected: Bool) -> Bool {
        alwaysOn || hovered || expanded || recentChange || activeAppSelected
    }

    /// First reads, missing windows, and metadata changes are not usage activity.
    public static func usageChanged(from old: [LimitBucket], to new: [LimitBucket]) -> Bool {
        new.contains { bucket in
            guard let previous = old.first(where: { $0.id == bucket.id }) else { return false }
            return bucket.windows.contains { window in
                guard let before = previous.windows.first(where: { $0.windowDurationMins == window.windowDurationMins }) else { return false }
                return before.usedPercent != window.usedPercent
            }
        }
    }
}
