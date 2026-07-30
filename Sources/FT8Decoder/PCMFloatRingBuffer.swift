import Foundation

public enum PCMFloatRingBufferError: Error, Equatable, Sendable {
    case invalidCapacity
}

public struct PCMFloatRingBuffer: Sendable {
    private var storage: [Float]
    private var readIndex: Int
    private var writeIndex: Int
    public private(set) var count: Int

    public let capacity: Int

    public init(capacity: Int) throws {
        guard capacity > 0 else {
            throw PCMFloatRingBufferError.invalidCapacity
        }
        self.capacity = capacity
        self.storage = Array(repeating: 0, count: capacity)
        self.readIndex = 0
        self.writeIndex = 0
        self.count = 0
    }

    public var isEmpty: Bool { count == 0 }
    public var isFull: Bool { count == capacity }
    public var availableCapacity: Int { capacity - count }

    @discardableResult
    public mutating func append(_ samples: [Float]) -> Int {
        guard !samples.isEmpty else { return 0 }

        var written = 0
        for sample in samples {
            if isFull {
                readIndex = (readIndex + 1) % capacity
                count -= 1
            }

            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            count += 1
            written += 1
        }
        return written
    }

    public func peek(count requestedCount: Int) -> [Float] {
        guard requestedCount > 0, count > 0 else { return [] }
        let amount = min(requestedCount, count)

        var output = [Float]()
        output.reserveCapacity(amount)

        var index = readIndex
        for _ in 0..<amount {
            output.append(storage[index])
            index = (index + 1) % capacity
        }
        return output
    }

    public func suffix(count requestedCount: Int) -> [Float] {
        guard requestedCount > 0, count > 0 else { return [] }
        let amount = min(requestedCount, count)
        let start = (writeIndex - amount + capacity) % capacity

        var output = [Float]()
        output.reserveCapacity(amount)

        var index = start
        for _ in 0..<amount {
            output.append(storage[index])
            index = (index + 1) % capacity
        }
        return output
    }

    @discardableResult
    public mutating func removeFirst(_ requestedCount: Int) -> [Float] {
        guard requestedCount > 0, count > 0 else { return [] }

        let amount = min(requestedCount, count)
        let output = peek(count: amount)
        readIndex = (readIndex + amount) % capacity
        count -= amount
        return output
    }

    public mutating func removeAll(keepingCapacity: Bool = true) {
        readIndex = 0
        writeIndex = 0
        count = 0

        if !keepingCapacity {
            storage = Array(repeating: 0, count: capacity)
        }
    }
}
