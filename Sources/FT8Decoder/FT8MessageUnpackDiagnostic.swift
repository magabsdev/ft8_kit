import Foundation
import FT8Protocol

/// Diagnostic description of a CRC-valid FT8 77-bit payload that could not
/// be converted into a displayable message.
///
/// This is diagnostic-only. It does not relax parity, CRC, or unpack gates.
public struct FT8MessageUnpackDiagnostic:
    Equatable,
    Sendable,
    CustomStringConvertible
{
    public let payloadHex: String
    public let payloadBits: String
    public let i3: Int
    public let n3: Int
    public let failure: String

    public init(
        payload: FT8BitBuffer,
        failure: Error
    ) {
        self.payloadHex = Self.hex(payload)
        self.payloadBits = payload.bits.map(String.init).joined()
        self.i3 = Self.value(payload, range: 74..<77)
        self.n3 = Self.value(payload, range: 71..<74)
        self.failure = String(describing: failure)
    }

    public var description: String {
        "payloadHex=\(payloadHex) "
            + "i3=\(i3) "
            + "n3=\(n3) "
            + "error=\(failure) "
            + "bits=\(payloadBits)"
    }

    private static func value(
        _ payload: FT8BitBuffer,
        range: Range<Int>
    ) -> Int {
        guard payload.count >= range.upperBound else {
            return -1
        }

        var value = 0
        for index in range {
            value = (value << 1) | Int(payload[index])
        }
        return value
    }

    private static func hex(
        _ payload: FT8BitBuffer
    ) -> String {
        payload.packedBytes()
            .map { String(format: "%02X", Int($0)) }
            .joined()
    }
}

public extension FT8MessageUnpackDiagnostic {
    init?(
        result: FT8LDPCResult,
        failure: Error
    ) {
        guard result.informationBits.count >= 77 else {
            return nil
        }

        let payload = FT8BitBuffer(
            Array(result.informationBits.bits.prefix(77))
        )

        self.init(payload: payload, failure: failure)
    }
}
