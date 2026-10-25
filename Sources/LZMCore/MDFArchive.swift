import Foundation

public enum MDFError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

public struct MDFEntry: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let kind: UInt8
    public let compressedSize: Int
    public let expandedSize: Int
    let payload: Range<Int>

    public var typeName: String {
        let types: [UInt8: String] = [0: "MCP", 1: "RCP", 2: "SNG", 3: "SNG v2", 4: "MST",
            5: "MDI", 6: "MIDI", 7: "SEQ", 8: "MCC", 9: "MM2", 10: "R36",
            0x20: L10n.text("音色 (MCP)"), 0x21: "CM6", 0x30: "GSD", 0x40: L10n.text("歌詞 (WRD)")]
        return types[kind] ?? L10n.format("種別 0x%02X", Int(kind))
    }
}

/// X68000 LZM MDF0: 160-byte archive header, followed by 48-byte entry headers
/// and MSB-first LZEXE-style token streams. All integer fields are big endian.
public struct MDFArchive: Sendable {
    public static let sizeLimit = 256 * 1024 * 1024
    public static let totalSizeLimit = 512 * 1024 * 1024
    public let title: String
    public let entries: [MDFEntry]
    private let bytes: [UInt8]

    public init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.sizeLimit else { throw MDFError.invalid(L10n.text("入力ファイルが256 MiBを超えています。")) }
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        guard data.count <= Self.sizeLimit else { throw MDFError.invalid(L10n.text("入力ファイルが256 MiBを超えています。")) }
        let bytes = [UInt8](data)
        guard bytes.count >= 160, Array(bytes[0..<6]) == Array("MDF0\r\n".utf8) else {
            throw MDFError.invalid(L10n.text("LZMのMDF0形式ではありません。対応するMDFファイルを選択してください。"))
        }
        self.bytes = bytes
        title = Self.text(Array(bytes[6..<70])).trimmingCharacters(in: .whitespacesAndNewlines)
        let count = Self.integer(bytes, at: 76)
        guard count > 0, count <= 4096 else { throw MDFError.invalid(L10n.text("格納ファイル数が不正です。")) }
        var result: [MDFEntry] = []
        var offset = 160
        var total = 0
        for index in 0..<count {
            guard offset <= bytes.count - 48 else { throw MDFError.invalid(L10n.text("格納ファイルのヘッダが途中で切れています。")) }
            let compressed = Self.integer(bytes, at: offset)
            let expanded = Self.integer(bytes, at: offset + 44)
            guard compressed > 0, compressed <= bytes.count - offset - 48 else {
                throw MDFError.invalid(L10n.text("圧縮データのサイズが不正、またはファイルが途中で切れています。"))
            }
            guard expanded <= Self.sizeLimit, expanded <= Self.totalSizeLimit - total else {
                throw MDFError.invalid(L10n.text("展開後のサイズが制限を超えています（1ファイル256 MiB、合計512 MiB）。"))
            }
            let name = Self.text(Array(bytes[(offset + 16)..<(offset + 44)]))
            guard !name.isEmpty else { throw MDFError.invalid(L10n.text("格納ファイル名が空です。")) }
            result.append(MDFEntry(id: index, name: name, kind: bytes[offset + 4],
                compressedSize: compressed, expandedSize: expanded,
                payload: (offset + 48)..<(offset + 48 + compressed)))
            total += expanded
            offset += 48 + compressed
        }
        entries = result
    }

    public func extract(_ entry: MDFEntry) throws -> Data {
        guard let own = entries.first(where: { $0.id == entry.id }), own.payload == entry.payload,
              own.expandedSize == entry.expandedSize else { throw MDFError.invalid(L10n.text("格納ファイル情報が一致しません。")) }
        var reader = TokenReader(bytes: bytes, range: own.payload)
        var output = [UInt8]()
        output.reserveCapacity(own.expandedSize)
        var tokens = 0
        while true {
            tokens += 1
            if tokens & 4095 == 0 { try Task.checkCancellation() }
            if try reader.bit() {
                guard output.count < own.expandedSize else { throw MDFError.invalid(L10n.text("展開サイズがヘッダの値を超えています。")) }
                output.append(try reader.byte())
                continue
            }
            let distance: Int
            let length: Int
            if try reader.bit() {
                let high = Int(try reader.byte())
                let low = Int(try reader.byte())
                let word = (high << 8) | low
                distance = 8192 - (word >> 3)
                let code = word & 7
                if code == 0 {
                    let extra = Int(try reader.byte())
                    if extra == 0 { break }
                    length = extra + 2
                } else { length = code + 2 }
            } else {
                let high = try reader.bit() ? 2 : 0
                let low = try reader.bit() ? 1 : 0
                length = high + low + 2
                distance = 256 - Int(try reader.byte())
            }
            guard distance <= output.count else { throw MDFError.invalid(L10n.text("圧縮データの参照位置が不正です。")) }
            guard length <= own.expandedSize - output.count else { throw MDFError.invalid(L10n.text("展開サイズがヘッダの値を超えています。")) }
            // Byte-wise copying deliberately supports overlapping references.
            for _ in 0..<length { output.append(output[output.count - distance]) }
        }
        guard output.count == own.expandedSize else { throw MDFError.invalid(L10n.text("展開後のサイズが一致しません。データが破損している可能性があります。")) }
        return Data(output)
    }

    private static func integer(_ bytes: [UInt8], at offset: Int) -> Int {
        bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }

    private static func text(_ bytes: [UInt8]) -> String {
        let bytes = Array(bytes.prefix(while: { $0 != 0 }))
        if let text = String(data: Data(bytes), encoding: .shiftJIS) { return text }
        // Old fixed-width comments can end in a partial/invalid character.
        // Recover character by character instead of interpreting the entire title as UTF-8.
        var text = ""
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let lead = (0x81...0x9f).contains(byte) || (0xe0...0xfc).contains(byte)
            let width = lead && index + 1 < bytes.count ? 2 : 1
            let data = Data(bytes[index..<(index + width)])
            if let character = String(data: data, encoding: .shiftJIS) {
                text += character
                index += width
            } else {
                text += "\u{fffd}"
                index += 1
            }
        }
        return text
    }
}

private struct TokenReader {
    let bytes: [UInt8]
    let range: Range<Int>
    var position: Int
    var flags: UInt8 = 0
    var remaining = 0

    init(bytes: [UInt8], range: Range<Int>) { self.bytes = bytes; self.range = range; position = range.lowerBound }
    mutating func byte() throws -> UInt8 {
        guard position < range.upperBound else { throw MDFError.invalid(L10n.text("圧縮データが途中で切れています（終端コードがありません）。")) }
        defer { position += 1 }
        return bytes[position]
    }
    mutating func bit() throws -> Bool {
        if remaining == 0 { flags = try byte(); remaining = 8 }
        let value = flags & 0x80 != 0
        flags <<= 1
        remaining -= 1
        return value
    }
}
