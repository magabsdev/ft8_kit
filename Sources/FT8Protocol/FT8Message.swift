import Foundation

public enum FT8Message: Equatable, Sendable {
    case freeText(String)
    case standard(to: String, from: String, extra: String)
    case telemetry(String)
    case unsupported(type: Int, subtype: Int, payloadHex: String)

    public var displayText: String {
        switch self {
        case .freeText(let value): return value
        case .standard(let to, let from, let extra):
            return [to, from, extra].filter { !$0.isEmpty }.joined(separator: " ")
        case .telemetry(let value): return value
        case .unsupported(let type, let subtype, let payloadHex):
            return "[FT8 type \(type).\(subtype) \(payloadHex)]"
        }
    }
}

public enum FT8ProtocolError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedCharacter(Character)
    case messageTooLong(Int)
    case invalidPayloadLength(Int)
    case unsupportedMessageType(type: Int, subtype: Int)
    case invalidPackedField

    public var errorDescription: String? {
        switch self {
        case .unsupportedCharacter(let character): return "Unsupported FT8 character: \(character)"
        case .messageTooLong(let count): return "FT8 free text is limited to 13 characters; received \(count)."
        case .invalidPayloadLength(let count): return "Expected 77 payload bits; received \(count)."
        case .unsupportedMessageType(let type, let subtype): return "Unsupported FT8 message type \(type).\(subtype)."
        case .invalidPackedField: return "The FT8 payload contains an invalid packed field."
        }
    }
}
