import Testing
@testable import FT8DSP

@Test func magnitudeWorks(){
 let r=FFTResult(real:[3],imaginary:[4])
 #expect(Spectrum.magnitude(from:r)[0] == 5)
}
