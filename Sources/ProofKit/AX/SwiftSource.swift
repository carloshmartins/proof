import Foundation

/// Swift source as bytes with string literals and comments blanked out (newlines kept),
/// so structural scanning never trips over a "(" or "{" inside a string or comment.
struct SwiftSource {
    let original: [UInt8]
    let masked: [UInt8]
    let lineStarts: [Int]

    init(_ text: String) {
        original = Array(text.utf8)
        masked = SwiftSource.mask(original)
        var starts = [0]
        for (i, c) in original.enumerated() where c == UInt8(ascii: "\n") { starts.append(i + 1) }
        lineStarts = starts
    }

    func line(at offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    func lineText(_ line: Int) -> String {
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] - 1 : original.count
        return String(decoding: original[start..<max(start, end)], as: UTF8.self)
    }

    // MARK: - Masking

    private enum Mode { case code, lineComment, blockComment(Int), string(hashes: Int, multiline: Bool) }

    static func mask(_ s: [UInt8]) -> [UInt8] {
        var out = s
        var modes: [Mode] = [.code]
        // For interpolation: paren depth at which each \( started, per string level.
        var interpParens: [Int] = []
        var parenDepth = 0
        var i = 0
        let quote = UInt8(ascii: "\""), hash = UInt8(ascii: "#"), slash = UInt8(ascii: "/"),
            star = UInt8(ascii: "*"), backslash = UInt8(ascii: "\\"), nl = UInt8(ascii: "\n"),
            lparen = UInt8(ascii: "("), rparen = UInt8(ascii: ")")

        func blank(_ k: Int) { if out[k] != nl { out[k] = UInt8(ascii: " ") } }
        func at(_ k: Int) -> UInt8 { k < s.count ? s[k] : 0 }

        while i < s.count {
            let c = s[i]
            switch modes.last! {
            case .code:
                if c == slash && at(i + 1) == slash { modes.append(.lineComment); blank(i); i += 1; continue }
                if c == slash && at(i + 1) == star { modes.append(.blockComment(1)); blank(i); blank(i + 1); i += 2; continue }
                if c == hash || c == quote {
                    var hashes = 0, k = i
                    while at(k) == hash { hashes += 1; k += 1 }
                    if at(k) == quote {
                        let multi = at(k + 1) == quote && at(k + 2) == quote
                        let openLen = (k - i) + (multi ? 3 : 1)
                        i += openLen
                        modes.append(.string(hashes: hashes, multiline: multi))
                        continue
                    }
                }
                if c == lparen { parenDepth += 1 }
                if c == rparen {
                    parenDepth -= 1
                    if let last = interpParens.last, parenDepth == last {
                        interpParens.removeLast()
                        modes.removeLast()      // back into the string
                        blank(i)
                        i += 1
                        continue
                    }
                }
                i += 1
            case .lineComment:
                if c == nl { modes.removeLast() } else { blank(i) }
                i += 1
            case .blockComment(let depth):
                if c == slash && at(i + 1) == star { modes[modes.count - 1] = .blockComment(depth + 1); blank(i); blank(i + 1); i += 2; continue }
                if c == star && at(i + 1) == slash {
                    blank(i); blank(i + 1); i += 2
                    if depth == 1 { modes.removeLast() } else { modes[modes.count - 1] = .blockComment(depth - 1) }
                    continue
                }
                blank(i); i += 1
            case .string(let hashes, let multiline):
                // Escape: backslash followed by `hashes` hash marks.
                if c == backslash {
                    var k = i + 1, h = 0
                    while h < hashes && at(k) == hash { h += 1; k += 1 }
                    if h == hashes {
                        if at(k) == lparen {
                            // Interpolation: code mode until the matching ")".
                            for x in i...k { blank(x) }
                            interpParens.append(parenDepth)
                            parenDepth += 1
                            modes.append(.code)
                            i = k + 1
                            continue
                        }
                        blank(i); if k < s.count { blank(k) }
                        i = k + 1
                        continue
                    }
                }
                if c == quote {
                    let closeQuotes = multiline ? 3 : 1
                    var ok = true
                    for q in 0..<closeQuotes where at(i + q) != quote { ok = false }
                    var h = 0
                    while ok && h < hashes { if at(i + closeQuotes + h) != hash { ok = false }; h += 1 }
                    if ok { i += closeQuotes + hashes; modes.removeLast(); continue }
                }
                if !multiline && c == nl { modes.removeLast(); i += 1; continue }   // unterminated; recover
                blank(i); i += 1
            }
        }
        return out
    }

    // MARK: - Structural helpers on the masked text

    func isIdentChar(_ c: UInt8) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    func skipSpace(_ i: Int) -> Int {
        var i = i
        while i < masked.count, masked[i] == 32 || masked[i] == 9 || masked[i] == 10 || masked[i] == 13 { i += 1 }
        return i
    }

    /// Given index of an opening bracket, returns index just past its match.
    func matching(_ i: Int) -> Int? {
        let open = masked[i]
        let close: UInt8 = open == UInt8(ascii: "(") ? UInt8(ascii: ")") : open == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
        var depth = 0
        var k = i
        while k < masked.count {
            if masked[k] == open { depth += 1 }
            else if masked[k] == close { depth -= 1; if depth == 0 { return k + 1 } }
            k += 1
        }
        return nil
    }

    func identifier(at i: Int) -> (String, Int)? {
        var k = i
        while k < masked.count, isIdentChar(masked[k]) { k += 1 }
        guard k > i else { return nil }
        return (String(decoding: masked[i..<k], as: UTF8.self), k)
    }

    /// Skips `(...)`, trailing `{...}` and labeled trailing closures `label: {...}`.
    func skipCallTail(_ i: Int) -> Int {
        var i = skipSpace(i)
        if i < masked.count, masked[i] == UInt8(ascii: "("), let e = matching(i) { i = e }
        while true {
            let j = skipSpace(i)
            if j < masked.count, masked[j] == UInt8(ascii: "{"), let e = matching(j) { i = e; continue }
            // labeled trailing closure:  label: { ... }
            if let (_, afterIdent) = identifier(at: j) {
                let colon = skipSpace(afterIdent)
                if colon < masked.count, masked[colon] == UInt8(ascii: ":") {
                    let brace = skipSpace(colon + 1)
                    if brace < masked.count, masked[brace] == UInt8(ascii: "{"), let e = matching(brace) { i = e; continue }
                }
            }
            return i
        }
    }

    /// Reads a `.modifier(...)` chain starting at `i`. Returns modifier names.
    func modifierChain(_ i: Int) -> [String] {
        var names: [String] = []
        var i = i
        while true {
            let dot = skipSpace(i)
            guard dot < masked.count, masked[dot] == UInt8(ascii: "."), let (name, end) = identifier(at: dot + 1) else { return names }
            names.append(name)
            i = skipCallTail(end)
        }
    }
}
