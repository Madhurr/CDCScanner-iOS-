import Foundation

/// A decoded CBOR data item (RFC 8949). Only what attestation documents need.
public indirect enum CBORValue: Hashable, Sendable {
    case unsigned(UInt64)
    /// Stored as the encoded argument `n`; the value is `-1 - n`.
    case negative(UInt64)
    case bytes(Data)
    case text(String)
    case array([CBORValue])
    case map([CBORValue: CBORValue])
    case tagged(UInt64, CBORValue)
    case bool(Bool)
    case null
    case undefined
    case simple(UInt8)
    case double(Double)

    public var intValue: Int? {
        switch self {
        case .unsigned(let value): return value <= UInt64(Int.max) ? Int(value) : nil
        case .negative(let n): return n < UInt64(Int.max) ? -1 - Int(n) : nil
        default: return nil
        }
    }
    public var uint64Value: UInt64? { if case .unsigned(let v) = self { return v }; return nil }
    public var bytesValue: Data? { if case .bytes(let v) = self { return v }; return nil }
    public var textValue: String? { if case .text(let v) = self { return v }; return nil }
    public var arrayValue: [CBORValue]? { if case .array(let v) = self { return v }; return nil }
    public var mapValue: [CBORValue: CBORValue]? { if case .map(let v) = self { return v }; return nil }

    public subscript(key: String) -> CBORValue? { mapValue?[.text(key)] }
    public subscript(key: Int) -> CBORValue? {
        key >= 0 ? mapValue?[.unsigned(UInt64(key))] : mapValue?[.negative(UInt64(-1 - key))]
    }
}

public enum CBORError: Error, Equatable, Sendable {
    case truncated
    case malformed(String)
    case unsupported(String)
    case trailingBytes
}

public enum CBORDecoder {
    /// Decodes exactly one data item; trailing bytes are an error.
    public static func decode(_ data: Data) throws -> CBORValue {
        var reader = Reader(data: data)
        let value = try reader.readItem(depth: 0)
        guard reader.isAtEnd else { throw CBORError.trailingBytes }
        return value
    }

    private struct Reader {
        let data: Data
        var offset: Int
        init(data: Data) { self.data = data; self.offset = data.startIndex }
        var isAtEnd: Bool { offset >= data.endIndex }

        mutating func readByte() throws -> UInt8 {
            guard offset < data.endIndex else { throw CBORError.truncated }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func readBytes(_ count: Int) throws -> Data {
            guard count >= 0, data.endIndex - offset >= count else { throw CBORError.truncated }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }

        mutating func readArgument(_ info: UInt8) throws -> UInt64? {
            switch info {
            case 0...23: return UInt64(info)
            case 24: return UInt64(try readByte())
            case 25: return try readBytes(2).reduce(0) { $0 << 8 | UInt64($1) }
            case 26: return try readBytes(4).reduce(0) { $0 << 8 | UInt64($1) }
            case 27: return try readBytes(8).reduce(0) { $0 << 8 | UInt64($1) }
            case 31: return nil // indefinite length
            default: throw CBORError.malformed("additional info \(info)")
            }
        }

        mutating func readItem(depth: Int) throws -> CBORValue {
            guard depth < 64 else { throw CBORError.malformed("nesting too deep") }
            let initial = try readByte()
            let major = initial >> 5
            let info = initial & 0x1f
            switch major {
            case 0:
                guard let value = try readArgument(info) else { throw CBORError.malformed("indefinite uint") }
                return .unsigned(value)
            case 1:
                guard let value = try readArgument(info) else { throw CBORError.malformed("indefinite negative") }
                return .negative(value)
            case 2:
                guard let length = try readArgument(info) else { throw CBORError.unsupported("indefinite byte string") }
                guard length <= UInt64(Int.max) else { throw CBORError.truncated }
                return .bytes(try readBytes(Int(length)))
            case 3:
                guard let length = try readArgument(info) else { throw CBORError.unsupported("indefinite text string") }
                guard length <= UInt64(Int.max) else { throw CBORError.truncated }
                guard let text = String(data: try readBytes(Int(length)), encoding: .utf8) else { throw CBORError.malformed("invalid UTF-8") }
                return .text(text)
            case 4:
                guard let count = try readArgument(info) else { throw CBORError.unsupported("indefinite array") }
                guard count <= 65536 else { throw CBORError.malformed("array too large") }
                var items: [CBORValue] = []
                items.reserveCapacity(Int(count))
                for _ in 0..<count { items.append(try readItem(depth: depth + 1)) }
                return .array(items)
            case 5:
                guard let count = try readArgument(info) else { throw CBORError.unsupported("indefinite map") }
                guard count <= 65536 else { throw CBORError.malformed("map too large") }
                var map: [CBORValue: CBORValue] = [:]
                for _ in 0..<count {
                    let key = try readItem(depth: depth + 1)
                    let value = try readItem(depth: depth + 1)
                    guard map.updateValue(value, forKey: key) == nil else { throw CBORError.malformed("duplicate map key") }
                }
                return .map(map)
            case 6:
                guard let tag = try readArgument(info) else { throw CBORError.malformed("indefinite tag") }
                return .tagged(tag, try readItem(depth: depth + 1))
            case 7:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 23: return .undefined
                case 0...19: return .simple(info)
                case 24: return .simple(try readByte())
                case 25:
                    let bits = try readBytes(2).reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
                    return .double(Double(Float16(bitPattern: bits)))
                case 26:
                    let bits = try readBytes(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                    return .double(Double(Float(bitPattern: bits)))
                case 27:
                    let bits = try readBytes(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                    return .double(Double(bitPattern: bits))
                default: throw CBORError.malformed("simple value \(info)")
                }
            default:
                throw CBORError.malformed("major type \(major)")
            }
        }
    }
}

/// Encodes the handful of CBOR shapes needed to rebuild a COSE `Sig_structure`.
enum CBOREncoder {
    static func encode(_ value: CBORValue) -> Data {
        var out = Data()
        append(value, to: &out)
        return out
    }

    private static func append(_ value: CBORValue, to out: inout Data) {
        switch value {
        case .unsigned(let v): appendHead(major: 0, argument: v, to: &out)
        case .negative(let n): appendHead(major: 1, argument: n, to: &out)
        case .bytes(let d): appendHead(major: 2, argument: UInt64(d.count), to: &out); out.append(d)
        case .text(let s): let d = Data(s.utf8); appendHead(major: 3, argument: UInt64(d.count), to: &out); out.append(d)
        case .array(let items): appendHead(major: 4, argument: UInt64(items.count), to: &out); items.forEach { append($0, to: &out) }
        case .map(let map):
            appendHead(major: 5, argument: UInt64(map.count), to: &out)
            // Canonical ordering: shorter encoded keys first, then bytewise.
            let pairs = map.map { (encode($0.key), $0.value) }.sorted { lhs, rhs in
                lhs.0.count != rhs.0.count ? lhs.0.count < rhs.0.count : lhs.0.lexicographicallyPrecedes(rhs.0)
            }
            for (key, value) in pairs { out.append(key); append(value, to: &out) }
        case .tagged(let tag, let inner): appendHead(major: 6, argument: tag, to: &out); append(inner, to: &out)
        case .bool(let b): out.append(b ? 0xf5 : 0xf4)
        case .null: out.append(0xf6)
        case .undefined: out.append(0xf7)
        case .simple(let v): v < 24 ? out.append(0xe0 | v) : out.append(contentsOf: [0xf8, v])
        case .double(let d): out.append(0xfb); var be = d.bitPattern.bigEndian; out.append(Data(bytes: &be, count: 8))
        }
    }

    private static func appendHead(major: UInt8, argument: UInt64, to out: inout Data) {
        let majorBits = major << 5
        switch argument {
        case 0...23: out.append(majorBits | UInt8(argument))
        case 24...0xff: out.append(majorBits | 24); out.append(UInt8(argument))
        case 0x100...0xffff: out.append(majorBits | 25); out.append(contentsOf: [UInt8(argument >> 8), UInt8(argument & 0xff)])
        case 0x10000...0xffff_ffff: out.append(majorBits | 26); (0..<4).reversed().forEach { out.append(UInt8((argument >> ($0 * 8)) & 0xff)) }
        default: out.append(majorBits | 27); (0..<8).reversed().forEach { out.append(UInt8((argument >> ($0 * 8)) & 0xff)) }
        }
    }
}
