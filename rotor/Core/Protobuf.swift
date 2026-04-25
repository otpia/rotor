import Foundation

// Minimal Protobuf wire-format parser, covering only the varint / length-delimited cases needed by GA migration
enum Protobuf {
    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
    }

    struct Field {
        let number: Int
        let value: Value
    }

    static func parse(_ data: Data) -> [Field]? {
        var fields: [Field] = []
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard let (tag, tagSize) = readVarint(data, from: cursor) else { return nil }
            cursor = data.index(cursor, offsetBy: tagSize)
            let wireType = Int(tag & 0x7)
            let number = Int(tag >> 3)

            switch wireType {
            case 0: // varint
                guard let (v, size) = readVarint(data, from: cursor) else { return nil }
                fields.append(Field(number: number, value: .varint(v)))
                cursor = data.index(cursor, offsetBy: size)
            case 1: // 64-bit
                guard data.distance(from: cursor, to: data.endIndex) >= 8 else { return nil }
                let slice = data[cursor..<data.index(cursor, offsetBy: 8)]
                let v = slice.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
                fields.append(Field(number: number, value: .fixed64(v)))
                cursor = data.index(cursor, offsetBy: 8)
            case 2: // length-delimited
                guard let (len, lenSize) = readVarint(data, from: cursor) else { return nil }
                cursor = data.index(cursor, offsetBy: lenSize)
                let length = Int(len)
                guard data.distance(from: cursor, to: data.endIndex) >= length else { return nil }
                let bytes = data[cursor..<data.index(cursor, offsetBy: length)]
                fields.append(Field(number: number, value: .bytes(Data(bytes))))
                cursor = data.index(cursor, offsetBy: length)
            case 5: // 32-bit
                guard data.distance(from: cursor, to: data.endIndex) >= 4 else { return nil }
                let slice = data[cursor..<data.index(cursor, offsetBy: 4)]
                let v = slice.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
                fields.append(Field(number: number, value: .fixed32(v)))
                cursor = data.index(cursor, offsetBy: 4)
            default:
                return nil
            }
        }
        return fields
    }

    private static func readVarint(_ data: Data, from start: Data.Index) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = start
        var count = 0
        while cursor < data.endIndex && count < 10 {
            let byte = data[cursor]
            result |= UInt64(byte & 0x7F) << shift
            cursor = data.index(after: cursor)
            count += 1
            if (byte & 0x80) == 0 {
                return (result, count)
            }
            shift += 7
        }
        return nil
    }
}
