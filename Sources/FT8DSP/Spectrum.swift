import Foundation

public enum Spectrum {
    public static func magnitude(from result: FFTResult)->[Float]{
        zip(result.real,result.imaginary).map{ sqrt($0*$0+$1*$1) }
    }
}
