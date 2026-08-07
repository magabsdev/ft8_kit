import Foundation
import FT8Protocol

public enum FT8MessageDecodeError: Error, Equatable, Sendable {
    case parityFailed(syndromeWeight: Int)
    case crcFailed
    case invalidInformationLength(Int)
    case unpackFailed(FT8ProtocolError)
    case emptyDecodedText
}

public struct FT8DecodedMessage: Equatable, Sendable {
    public let message: FT8Message
    public let text: String
    public let payload: FT8BitBuffer
    public let messageWithCRC: FT8BitBuffer
    public let codeword: FT8BitBuffer
    public let iterations: Int
    public let confidence: Float

    public init(
        message: FT8Message,
        payload: FT8BitBuffer,
        messageWithCRC: FT8BitBuffer,
        codeword: FT8BitBuffer,
        iterations: Int,
        confidence: Float
    ) {
        self.message = message
        self.text = message.displayText
        self.payload = payload
        self.messageWithCRC = messageWithCRC
        self.codeword = codeword
        self.iterations = iterations
        self.confidence = min(max(confidence, 0), 1)
    }
}

public struct FT8MessageDecoder: Sendable {
    public init() {}

    public func decode(
        _ result: FT8LDPCResult,
        softSymbols: FT8SoftSymbols? = nil
    ) throws -> FT8DecodedMessage {
        guard result.parityPassed else {
            throw FT8MessageDecodeError.parityFailed(
                syndromeWeight: result.syndromeWeight
            )
        }
        guard result.informationBits.count == 91 else {
            throw FT8MessageDecodeError.invalidInformationLength(
                result.informationBits.count
            )
        }
        guard result.crcPassed, FT8CRC.validate(result.informationBits) else {
            throw FT8MessageDecodeError.crcFailed
        }

        let payload = FT8BitBuffer(
            Array(result.informationBits.bits.prefix(77))
        )

        let message: FT8Message
        do {
            message = try FT8MessageCodec.unpack(payload)
        } catch let error as FT8ProtocolError {
            throw FT8MessageDecodeError.unpackFailed(error)
        }

        // WSJT-X-style acceptance gate: parity + CRC are necessary, but the
        // payload must also unpack into a meaningful protocol message.
        // Reject CRC-valid reserved/degenerate payloads that render as blank.
        let decodedText = message.displayText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !decodedText.isEmpty else {
            throw FT8MessageDecodeError.emptyDecodedText
        }

        return FT8DecodedMessage(
            message: message,
            payload: payload,
            messageWithCRC: result.informationBits,
            codeword: result.codeword,
            iterations: result.iterations,
            confidence: confidence(
                result: result,
                softSymbols: softSymbols
            )
        )
    }

    private func confidence(
        result: FT8LDPCResult,
        softSymbols: FT8SoftSymbols?
    ) -> Float {
        let symbolConfidence = softSymbols?.averageConfidence ?? 1
        let iterationPenalty = min(Float(result.iterations) / 50, 1)
        let decoderConfidence = 1 - 0.35 * iterationPenalty
        return 0.65 * symbolConfidence + 0.35 * decoderConfidence
    }
}
