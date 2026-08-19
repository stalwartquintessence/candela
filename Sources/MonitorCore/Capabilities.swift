// Parser for the DDC/CI capabilities string, for example:
//   (prot(monitor)type(LCD)model(Z27)cmds(01 02 03 07 0C E3 F3)vcp(02 04 10 12 14(05 08 0B) 60(0F 11 1B) 62)mccs_ver(2.2))
// Real monitors are sloppy: missing outer parentheses, missing spaces between codes, trailing
// garbage and unbalanced parentheses all occur, so the parser is deliberately lenient.

import Foundation

public struct Capabilities: Equatable, Sendable {
    public var raw: String
    /// Top-level entries, for example ["prot": "monitor", "type": "LCD", "model": "Z27"].
    public var fields: [String: String]
    /// Supported VCP codes mapped to their allowed values (empty for continuous features).
    public var vcp: [UInt8: [UInt16]]
    /// Supported DDC/CI command opcodes from `cmds(...)`.
    public var commands: [UInt8]

    public var model: String? { fields["model"] }
    public var type: String? { fields["type"] }
    public var mccsVersion: String? { fields["mccs_ver"] }
    public var vcpCodes: [UInt8] { vcp.keys.sorted() }

    public func supports(_ code: UInt8) -> Bool { vcp[code] != nil }

    /// Returns nil when the string contains no recognizable `key(value)` entries.
    public static func parse(_ string: String) -> Capabilities? {
        let fields = parseFields(string)
        guard !fields.isEmpty else { return nil }
        let vcp = fields["vcp"].map(parseVCPList) ?? [:]
        let commands = fields["cmds"].map { parseHexList($0) } ?? []
        return Capabilities(raw: string, fields: fields, vcp: vcp, commands: commands)
    }

    // MARK: Parsing helpers

    /// Split "key(value)key2(value2)" into a dictionary, keeping nested parentheses in values.
    static func parseFields(_ string: String) -> [String: String] {
        var chars = Array(string.trimmingCharacters(in: .whitespacesAndNewlines))
        // Strip one pair of outer parentheses when present.
        if chars.first == "(" {
            chars.removeFirst()
            if chars.last == ")" { chars.removeLast() }
        }

        var result: [String: String] = [:]
        var i = 0
        while i < chars.count {
            // Read a key made of letters, digits and underscores.
            var key = ""
            while i < chars.count, chars[i] != "(" {
                if chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { key.append(chars[i]) }
                i += 1
            }
            guard i < chars.count else { break }
            i += 1 // skip "("
            var depth = 1
            var value = ""
            while i < chars.count {
                let c = chars[i]
                if c == "(" { depth += 1 }
                if c == ")" {
                    depth -= 1
                    if depth == 0 { i += 1; break }
                }
                value.append(c)
                i += 1
            }
            if !key.isEmpty { result[key.lowercased()] = value.trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    /// Parse "02 04 10 14(05 08 0B) 60(0F 11)" or the same without spaces.
    static func parseVCPList(_ text: String) -> [UInt8: [UInt16]] {
        let chars = Array(text)
        var result: [UInt8: [UInt16]] = [:]
        var i = 0
        func skipSpace() { while i < chars.count, chars[i].isWhitespace { i += 1 } }
        func readHexByte() -> UInt8? {
            guard i + 1 < chars.count, chars[i].isHexDigit, chars[i + 1].isHexDigit,
                  let v = UInt8(String(chars[i ... i + 1]), radix: 16) else { return nil }
            i += 2
            return v
        }
        while i < chars.count {
            skipSpace()
            guard i < chars.count else { break }
            guard let code = readHexByte() else { i += 1; continue }
            skipSpace()
            var values: [UInt16] = []
            if i < chars.count, chars[i] == "(" {
                i += 1
                while i < chars.count, chars[i] != ")" {
                    skipSpace()
                    if i < chars.count, chars[i] == ")" { break }
                    if let v = readHexByte() { values.append(UInt16(v)) } else { i += 1 }
                }
                i += 1 // skip ")"
            }
            result[code] = values
        }
        return result
    }

    static func parseHexList(_ text: String) -> [UInt8] {
        parseVCPList(text).keys.sorted()
    }
}
