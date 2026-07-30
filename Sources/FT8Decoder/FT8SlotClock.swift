import Foundation

public struct FT8SlotClock: Equatable, Sendable {
    public var slotDuration: TimeInterval

    public init(slotDuration: TimeInterval = 15) {
        self.slotDuration = slotDuration
    }

    public func slotStart(containing date: Date) -> Date {
        guard slotDuration > 0 else { return date }
        let seconds = date.timeIntervalSince1970
        let slot = floor(seconds / slotDuration) * slotDuration
        return Date(timeIntervalSince1970: slot)
    }

    public func nextSlotStart(after date: Date) -> Date {
        slotStart(containing: date)
            .addingTimeInterval(slotDuration)
    }

    public func progress(at date: Date) -> Double {
        guard slotDuration > 0 else { return 0 }
        let start = slotStart(containing: date)
        return min(
            max(date.timeIntervalSince(start) / slotDuration, 0),
            1
        )
    }

    public func slotIndex(containing date: Date) -> Int64 {
        guard slotDuration > 0 else { return 0 }
        return Int64(
            floor(date.timeIntervalSince1970 / slotDuration)
        )
    }
}
