import Accelerate

public struct FFTResult {
    public let real:[Float]
    public let imaginary:[Float]
    public init(real:[Float], imaginary:[Float]) {
        self.real=real
        self.imaginary=imaginary
    }
}

public enum WindowFunction {
    case rectangular, hann, hamming, blackman
}

public final class FFT {
    public let size:Int
    public init(size:Int){ self.size=size }
}
