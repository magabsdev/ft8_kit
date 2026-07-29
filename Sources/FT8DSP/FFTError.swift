import Foundation

public enum FFTError: Error, Equatable, Sendable {
    case sizeMustBePowerOfTwo(Int)
    case sizeMustBeAtLeastTwo(Int)
    case incorrectInputCount(expected: Int, actual: Int)
    case unavailable
}
