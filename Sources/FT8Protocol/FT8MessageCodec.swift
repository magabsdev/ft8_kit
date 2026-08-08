import Foundation

public enum FT8MessageCodec {
    private static let max22: UInt32 = 4_194_304
    private static let nTokens: UInt32 = 2_063_592
    private static let maxGrid4: UInt16 = 32_400

    public static func pack(_ message: FT8Message) throws -> FT8BitBuffer {
        switch message {
        case .freeText(let text):
            return try packFreeText(text)
        case .standard(let to, let from, let extra):
            return try packStandard(to: to, from: from, extra: extra)
        case .telemetry, .structured, .unsupported:
            throw FT8ProtocolError.unsupportedMessageType(type: -1, subtype: -1)
        }
    }

    public static func unpack(_ payload: FT8BitBuffer) throws -> FT8Message {
        guard payload.count == FT8Constants.informationBitCount else {
            throw FT8ProtocolError.invalidPayloadLength(payload.count)
        }

        // WSJT-X packjt77.f90 reads c77(72:77) as n3,i3.
        let n3 = Int(value(payload.bits, range: 71..<74))
        let i3 = Int(value(payload.bits, range: 74..<77))

        switch (i3, n3) {
        case (0, 0):
            return unpackFreeText(payload)
        case (0, 1):
            return try unpackDXpedition(payload)
        case (0, 3), (0, 4):
            return try unpackFieldDay(payload, n3: n3)
        case (0, 5):
            return .telemetry(unpackTelemetry(payload))
        case (1, _), (2, _):
            return try unpackStandard(payload, i3: i3)
        case (3, _):
            return try unpackRTTY(payload)
        case (4, _):
            return try unpackNonstandard(payload)
        case (5, _):
            return try unpackVHFContest(payload)
        default:
            throw FT8ProtocolError.unsupportedMessageType(type: i3, subtype: n3)
        }
    }

    private static func unpackFreeText(_ payload: FT8BitBuffer) -> FT8Message {
        var number = FT8BitBuffer(Array(payload.bits[0..<71]))
        var characters = [Character](repeating: " ", count: 13)
        for index in stride(from: 12, through: 0, by: -1) {
            characters[index] = FT8Constants.freeTextAlphabet[number.divide(by: 42)]
        }
        return .freeText(String(characters).trimmingCharacters(in: .whitespaces))
    }

    private static func unpackStandard(_ payload: FT8BitBuffer, i3: Int) throws -> FT8Message {
        let n29a = UInt32(value(payload.bits, range: 0..<29))
        let n29b = UInt32(value(payload.bits, range: 29..<58))
        let ir = Int(payload.bits[58])
        let grid = UInt16(value(payload.bits, range: 59..<74))

        let callTo = try unpack28(n29a >> 1, suffix: Int(n29a & 1), i3: i3)
        let callFrom = try unpack28(n29b >> 1, suffix: Int(n29b & 1), i3: i3)
        let extra = unpackGrid(grid, ir: ir)

        if callTo == "CQ" || callTo.hasPrefix("CQ ") {
            if ir == 1 { throw FT8ProtocolError.invalidPackedField }
            if grid > maxGrid4 {
                let report = Int(grid - maxGrid4)
                if report >= 2 { throw FT8ProtocolError.invalidPackedField }
            }
        }

        return .standard(to: callTo, from: callFrom, extra: extra)
    }

    private static func unpack28(_ raw: UInt32, suffix: Int, i3: Int) throws -> String {
        if raw < nTokens {
            switch raw {
            case 0: return "DE"
            case 1: return "QRZ"
            case 2: return "CQ"
            case 3...1002:
                return String(format: "CQ %03u", raw - 3)
            case 1003...532_443:
                var n = raw - 1003
                var chars = [Character](repeating: " ", count: 4)
                let alphabet = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                for index in stride(from: 3, through: 0, by: -1) {
                    chars[index] = alphabet[Int(n % 27)]
                    n /= 27
                }
                return "CQ " + String(chars).trimmingCharacters(in: .whitespaces)
            default:
                throw FT8ProtocolError.invalidPackedField
            }
        }

        var n = raw - nTokens
        if n < max22 {
            return String(format: "<%06X>", n)
        }
        n -= max22

        let lettersSpace = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let alphanumeric = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let alphanumericSpace = Array(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let numeric = Array("0123456789")

        var callsign = [Character](repeating: " ", count: 6)
        callsign[5] = lettersSpace[Int(n % 27)]; n /= 27
        callsign[4] = lettersSpace[Int(n % 27)]; n /= 27
        callsign[3] = lettersSpace[Int(n % 27)]; n /= 27
        callsign[2] = numeric[Int(n % 10)]; n /= 10
        callsign[1] = alphanumeric[Int(n % 36)]; n /= 36
        callsign[0] = alphanumericSpace[Int(n % 37)]

        var result = String(callsign).trimmingCharacters(in: .whitespaces)
        if result.hasPrefix("3D0"), result.count > 3 {
            result = "3DA0" + String(result.dropFirst(3))
        } else if result.first == "Q", result.count > 1,
                  String(result.dropFirst().prefix(1)).rangeOfCharacter(from: .letters) != nil {
            result = "3X" + String(result.dropFirst())
        }

        guard result.count >= 3 else { throw FT8ProtocolError.invalidPackedField }
        if suffix != 0 {
            if i3 == 1 { result += "/R" }
            else if i3 == 2 { result += "/P" }
            else { throw FT8ProtocolError.invalidPackedField }
        }
        return result
    }

    private static func unpackGrid(_ packed: UInt16, ir: Int) -> String {
        if packed <= maxGrid4 {
            var n = packed
            let d2 = Int(n % 10); n /= 10
            let d1 = Int(n % 10); n /= 10
            let b = Int(n % 18); n /= 18
            let a = Int(n % 18)
            let grid = "\(Character(UnicodeScalar(65 + a)!))\(Character(UnicodeScalar(65 + b)!))\(d1)\(d2)"
            return ir == 1 ? "R \(grid)" : grid
        }

        let report = Int(packed - maxGrid4)
        switch report {
        case 1: return ""
        case 2: return "RRR"
        case 3: return "RR73"
        case 4: return "73"
        default:
            let value = report - 35
            let formatted = String(format: "%+03d", value)
            return ir == 1 ? "R\(formatted)" : formatted
        }
    }


    // MARK: - WSJT-X unpack77 forms

    private static let arrlSections = [
        "AB","AK","AL","AR","AZ","BC","CO","CT","DE","EB",
        "EMA","ENY","EPA","EWA","GA","GTA","IA","ID","IL","IN",
        "KS","KY","LA","LAX","MAR","MB","MDC","ME","MI","MN",
        "MO","MS","MT","NC","ND","NE","NFL","NH","NL","NLI",
        "NM","NNJ","NNY","NT","NTX","NV","OH","OK","ONE","ONN",
        "ONS","OR","ORG","PAC","PR","QC","RI","SB","SC","SCV",
        "SD","SDG","SF","SFL","SJV","SK","SNJ","STX","SV","TN",
        "UT","VA","VI","VT","WCF","WI","WMA","WNY","WPA","WTX",
        "WV","WWA","WY","DX"
    ]

    private static let usCanadaMultipliers = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
        "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
        "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
        "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY",
        "NB","NS","QC","ON","MB","SK","AB","BC","NWT","NF",
        "LB","NU","YT","PEI","DC"
    ]

    private static func unpackDXpedition(_ payload: FT8BitBuffer) throws -> FT8Message {
        let n28a = UInt32(value(payload.bits, range: 0..<28))
        let n28b = UInt32(value(payload.bits, range: 28..<56))
        let n10 = Int(value(payload.bits, range: 56..<66))
        let n5 = Int(value(payload.bits, range: 66..<71))

        guard n28a > 2, n28b > 2 else {
            throw FT8ProtocolError.invalidPackedField
        }

        let call1 = try unpack28(n28a, suffix: 0, i3: 1)
        let call2 = try unpack28(n28b, suffix: 0, i3: 1)
        let call3 = hashPlaceholder(bits: 10, value: n10)
        let report = 2 * n5 - 30
        return .structured("\(call1) RR73; \(call2) \(call3) \(signed2(report))")
    }

    private static func unpackFieldDay(_ payload: FT8BitBuffer, n3: Int) throws -> FT8Message {
        let n28a = UInt32(value(payload.bits, range: 0..<28))
        let n28b = UInt32(value(payload.bits, range: 28..<56))
        let ir = Int(payload.bits[56])
        let intx = Int(value(payload.bits, range: 57..<61))
        let nclass = Int(value(payload.bits, range: 61..<64))
        let isec = Int(value(payload.bits, range: 64..<71))

        guard n28a > 2, n28b > 2,
              (1...arrlSections.count).contains(isec) else {
            throw FT8ProtocolError.invalidPackedField
        }

        let call1 = try unpack28(n28a, suffix: 0, i3: 1)
        let call2 = try unpack28(n28b, suffix: 0, i3: 1)
        let ntx = intx + 1 + (n3 == 4 ? 16 : 0)
        let exchange = "\(ntx)\(Character(UnicodeScalar(65 + nclass)!))"
        let section = arrlSections[isec - 1]
        let text = ir == 1
            ? "\(call1) \(call2) R \(exchange) \(section)"
            : "\(call1) \(call2) \(exchange) \(section)"
        return .structured(text)
    }

    private static func unpackTelemetry(_ payload: FT8BitBuffer) -> String {
        let a = value(payload.bits, range: 0..<23)
        let b = value(payload.bits, range: 23..<47)
        let c = value(payload.bits, range: 47..<71)
        let raw = String(format: "%06llX%06llX%06llX", a, b, c)
        let trimmed = raw.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? "0" : String(trimmed).lowercased()
    }

    private static func unpackRTTY(_ payload: FT8BitBuffer) throws -> FT8Message {
        let itu = Int(payload.bits[0])
        let n28a = UInt32(value(payload.bits, range: 1..<29))
        let n28b = UInt32(value(payload.bits, range: 29..<57))
        let ir = Int(payload.bits[57])
        let irpt = Int(value(payload.bits, range: 58..<61))
        let nexch = Int(value(payload.bits, range: 61..<74))

        let call1 = try unpack28(n28a, suffix: 0, i3: 1)
        let call2 = try unpack28(n28b, suffix: 0, i3: 1)
        let report = "5\(irpt + 2)9"

        let exchange: String
        if nexch > 8000 {
            let multiplier = nexch - 8000
            guard (1...usCanadaMultipliers.count).contains(multiplier) else {
                throw FT8ProtocolError.invalidPackedField
            }
            exchange = usCanadaMultipliers[multiplier - 1]
        } else {
            guard (1...7999).contains(nexch) else {
                throw FT8ProtocolError.invalidPackedField
            }
            exchange = String(format: "%04d", nexch)
        }

        var fields = [call1, call2]
        if ir == 1 { fields.append("R") }
        fields += [report, exchange]
        let core = fields.joined(separator: " ")
        return .structured(itu == 1 ? "TU; \(core)" : core)
    }

    private static func unpackNonstandard(_ payload: FT8BitBuffer) throws -> FT8Message {
        let n12 = Int(value(payload.bits, range: 0..<12))
        var n58 = value(payload.bits, range: 12..<70)
        let iflip = Int(payload.bits[70])
        let nrpt = Int(value(payload.bits, range: 71..<73))
        let icq = Int(payload.bits[73])

        let alphabet = Array(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ/")
        var chars = [Character](repeating: " ", count: 11)
        for index in stride(from: 10, through: 0, by: -1) {
            chars[index] = alphabet[Int(n58 % 38)]
            n58 /= 38
        }
        let nonstandard = String(chars).trimmingCharacters(in: .whitespaces)
        guard !nonstandard.isEmpty else {
            throw FT8ProtocolError.invalidPackedField
        }

        let hashed = hashPlaceholder(bits: 12, value: n12)
        let call1 = iflip == 0 ? hashed : nonstandard
        let call2 = iflip == 0 ? nonstandard : hashed

        if icq == 1 {
            guard iflip == 1 else { throw FT8ProtocolError.invalidPackedField }
            return .structured("CQ \(call2)")
        }

        let suffix: String
        switch nrpt {
        case 0: suffix = ""
        case 1: suffix = " RRR"
        case 2: suffix = " RR73"
        case 3: suffix = " 73"
        default: throw FT8ProtocolError.invalidPackedField
        }
        return .structured("\(call1) \(call2)\(suffix)")
    }

    private static func unpackVHFContest(_ payload: FT8BitBuffer) throws -> FT8Message {
        let n12 = Int(value(payload.bits, range: 0..<12))
        let n22 = Int(value(payload.bits, range: 12..<34))
        let ir = Int(payload.bits[34])
        let irpt = Int(value(payload.bits, range: 35..<38))
        let iserial = Int(value(payload.bits, range: 38..<49))
        let igrid6 = Int(value(payload.bits, range: 49..<74))

        guard (0...18_662_399).contains(igrid6) else {
            throw FT8ProtocolError.invalidPackedField
        }

        let call1 = hashPlaceholder(bits: 12, value: n12)
        let call2 = hashPlaceholder(bits: 22, value: n22)
        let exchange = String(format: "%02d%04d", 52 + irpt, iserial)
        let grid6 = unpackGrid6(igrid6)

        let text = ir == 1
            ? "\(call1) \(call2) R \(exchange) \(grid6)"
            : "\(call1) \(call2) \(exchange) \(grid6)"
        return .structured(text)
    }

    private static func unpackGrid6(_ packed: Int) -> String {
        var n = packed
        let f = n % 24; n /= 24
        let e = n % 24; n /= 24
        let d = n % 10; n /= 10
        let c = n % 10; n /= 10
        let b = n % 18; n /= 18
        let a = n % 18
        return "\(Character(UnicodeScalar(65 + a)!))\(Character(UnicodeScalar(65 + b)!))\(c)\(d)\(Character(UnicodeScalar(65 + e)!))\(Character(UnicodeScalar(65 + f)!))"
    }

    private static func hashPlaceholder(bits: Int, value: Int) -> String {
        return "<HASH\(bits):\(String(value, radix: 16).uppercased())>"
    }

    private static func signed2(_ value: Int) -> String {
        value >= 0 ? String(format: "+%02d", value) : String(format: "-%02d", abs(value))
    }

    private static func packFreeText(_ input: String) throws -> FT8BitBuffer {
        let upper = input.uppercased()
        guard upper.count <= 13 else { throw FT8ProtocolError.messageTooLong(upper.count) }
        let padded = upper.padding(toLength: 13, withPad: " ", startingAt: 0)
        var number = FT8BitBuffer(count: 71)
        for character in padded {
            guard let index = FT8Constants.freeTextAlphabet.firstIndex(of: character) else {
                throw FT8ProtocolError.unsupportedCharacter(character)
            }
            number.multiply(by: 42)
            number.add(index)
        }
        return FT8BitBuffer(number.bits + [UInt8](repeating: 0, count: 6))
    }

    private static func packStandard(to: String, from: String, extra: String) throws -> FT8BitBuffer {
        let (toValue, toSuffix) = try pack28(to)
        let (fromValue, fromSuffix) = try pack28(from)
        let i3 = (to.uppercased().hasSuffix("/P") || from.uppercased().hasSuffix("/P")) ? 2 : 1
        let (gridValue, ir) = try packGrid(extra)

        var bits = [UInt8]()
        append(UInt64((toValue << 1) | UInt32(toSuffix)), width: 29, to: &bits)
        append(UInt64((fromValue << 1) | UInt32(fromSuffix)), width: 29, to: &bits)
        bits.append(UInt8(ir))
        append(UInt64(gridValue), width: 15, to: &bits)
        append(UInt64(i3), width: 3, to: &bits)
        return FT8BitBuffer(bits)
    }

    private static func pack28(_ input: String) throws -> (UInt32, Int) {
        let upper = input.uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if upper == "DE" { return (0, 0) }
        if upper == "QRZ" { return (1, 0) }
        if upper == "CQ" { return (2, 0) }

        // WSJT-X c28 special tokens:
        //   CQ nnn   -> values 3...1002
        //   CQ aaaa  -> values 1003...532443
        //
        // The alpha form is right-justified in a four-character base-27
        // field, matching packjt77.f90's ADJUSTR behaviour.
        if upper.hasPrefix("CQ ") {
            let modifier = String(upper.dropFirst(3))
                .trimmingCharacters(in: .whitespaces)

            if modifier.count == 3,
               modifier.allSatisfy(\.isNumber),
               let number = UInt32(modifier),
               number <= 999 {
                return (3 + number, 0)
            }

            if (1...4).contains(modifier.count),
               modifier.allSatisfy({ $0 >= "A" && $0 <= "Z" }) {
                let alphabet = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                let padded = String(
                    repeating: " ",
                    count: 4 - modifier.count
                ) + modifier

                var value: UInt32 = 0
                for character in padded {
                    guard let index = alphabet.firstIndex(of: character) else {
                        throw FT8ProtocolError.invalidPackedField
                    }
                    value = value * 27 + UInt32(index)
                }

                return (1003 + value, 0)
            }

            throw FT8ProtocolError.invalidPackedField
        }

        var suffix = 0
        var base = upper
        if base.hasSuffix("/R") || base.hasSuffix("/P") {
            suffix = 1
            base.removeLast(2)
        }

        var chars = [Character](repeating: " ", count: 6)
        let source = Array(base)
        if source.count <= 6, source.count >= 3 {
            if source.count > 2, source[2].isNumber {
                for index in source.indices { chars[index] = source[index] }
            } else if source.count > 1, source[1].isNumber, source.count <= 5 {
                for index in source.indices { chars[index + 1] = source[index] }
            }
        }

        let a0 = Array(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let a1 = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let digits = Array("0123456789")
        let suffixAlphabet = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard let i0 = a0.firstIndex(of: chars[0]),
              let i1 = a1.firstIndex(of: chars[1]),
              let i2 = digits.firstIndex(of: chars[2]),
              let i3 = suffixAlphabet.firstIndex(of: chars[3]),
              let i4 = suffixAlphabet.firstIndex(of: chars[4]),
              let i5 = suffixAlphabet.firstIndex(of: chars[5]) else {
            throw FT8ProtocolError.invalidPackedField
        }

        var n = UInt32(i0)
        n = n * 36 + UInt32(i1)
        n = n * 10 + UInt32(i2)
        n = n * 27 + UInt32(i3)
        n = n * 27 + UInt32(i4)
        n = n * 27 + UInt32(i5)
        return (nTokens + max22 + n, suffix)
    }

    private static func packGrid(_ input: String) throws -> (UInt16, Int) {
        let upper = input.uppercased()
        if upper.isEmpty { return (maxGrid4 + 1, 0) }
        if upper == "RRR" { return (maxGrid4 + 2, 0) }
        if upper == "RR73" { return (maxGrid4 + 3, 0) }
        if upper == "73" { return (maxGrid4 + 4, 0) }

        var report = upper
        var ir = 0
        if report.hasPrefix("R+") || report.hasPrefix("R-") {
            ir = 1
            report.removeFirst()
        }
        if let value = Int(report), (-50...49).contains(value) {
            return (maxGrid4 + UInt16(35 + value), ir)
        }

        let chars = Array(upper)
        guard chars.count == 4,
              let a = chars[0].asciiValue, let b = chars[1].asciiValue,
              (65...82).contains(a), (65...82).contains(b),
              let d1 = chars[2].wholeNumberValue, let d2 = chars[3].wholeNumberValue else {
            throw FT8ProtocolError.invalidPackedField
        }
        var n = UInt16(a - 65)
        n = n * 18 + UInt16(b - 65)
        n = n * 10 + UInt16(d1)
        n = n * 10 + UInt16(d2)
        return (n, 0)
    }

    private static func value(_ bits: [UInt8], range: Range<Int>) -> UInt64 {
        var result: UInt64 = 0
        for index in range { result = (result << 1) | UInt64(bits[index]) }
        return result
    }

    private static func append(_ value: UInt64, width: Int, to bits: inout [UInt8]) {
        for shift in stride(from: width - 1, through: 0, by: -1) {
            bits.append(UInt8((value >> UInt64(shift)) & 1))
        }
    }

    private static func payloadHex(_ bits: ArraySlice<UInt8>) -> String {
        var padded = Array(bits)
        while padded.count % 8 != 0 { padded.append(0) }
        return stride(from: 0, to: padded.count, by: 8).map { offset in
            var byte: UInt8 = 0
            for bit in padded[offset..<offset + 8] { byte = (byte << 1) | bit }
            return String(format: "%02X", byte)
        }.joined()
    }
}

public extension FT8MessageCodec {
    static func pack(_ text: String) throws -> FT8BitBuffer {
        let normalised = text.uppercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let fields = normalised.split(separator: " ").map(String.init)

        if fields.count == 3 {
            if let standard = try? pack(
                .standard(
                    to: fields[0],
                    from: fields[1],
                    extra: fields[2]
                )
            ) {
                return standard
            }
        }

        if fields.count == 4, fields[0] == "CQ" {
            if let standard = try? pack(
                .standard(
                    to: "CQ \(fields[1])",
                    from: fields[2],
                    extra: fields[3]
                )
            ) {
                return standard
            }
        }

        return try pack(.freeText(normalised))
    }
}
