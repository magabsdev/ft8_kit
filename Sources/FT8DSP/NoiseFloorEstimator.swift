import Foundation

public enum NoiseFloorEstimator {
    public static func median(of values: [Float]) -> Float {
        percentile(of: values, percentile: 0.5)
    }

    public static func percentile(
        of values: [Float],
        percentile: Float
    ) -> Float {
        guard !values.isEmpty else { return 0 }

        let p = min(max(percentile, 0), 1)
        let sorted = values.sorted()
        let position = p * Float(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))

        if lower == upper { return sorted[lower] }

        let fraction = position - Float(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    public static func trimmedMean(
        of values: [Float],
        trimmingFraction: Float = 0.1
    ) -> Float {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let trim = Int(
            Float(sorted.count) * min(max(trimmingFraction, 0), 0.49)
        )
        let lower = trim
        let upper = sorted.count - trim
        guard lower < upper else {
            return sorted.reduce(0, +) / Float(sorted.count)
        }

        let slice = sorted[lower..<upper]
        return slice.reduce(0, +) / Float(slice.count)
    }

    public static func rollingMedian(
        values: [Float],
        radius: Int
    ) -> [Float] {
        guard radius > 0 else { return values }

        return values.indices.map { index in
            let low = max(0, index - radius)
            let high = min(values.count, index + radius + 1)
            return median(of: Array(values[low..<high]))
        }
    }
}
