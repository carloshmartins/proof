import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct AXFinding: Codable, Equatable {
    public let file: String
    public let line: Int
    public let kind: String       // "swiftui" | "uikit" | "ib" | "runtime"
    public let control: String
    public let snippet: String
}

public struct AXScanReport: Report, Decodable {
    public let findings: [AXFinding]
    public let filesScanned: Int

    public var text: String {
        guard !findings.isEmpty else { return "AX SCAN clean · \(filesScanned) files scanned" }
        let byFile = Dictionary(grouping: findings, by: \.file)
        var out = ["AX SCAN \(findings.count) missing identifier\(findings.count == 1 ? "" : "s") in \(byFile.count) file\(byFile.count == 1 ? "" : "s") · \(filesScanned) files scanned"]
        for file in byFile.keys.sorted() {
            out.append(file)
            for f in byFile[file]!.sorted(by: { $0.line < $1.line }) {
                out.append("  \(f.line)  \(f.snippet)")
            }
        }
        return out.joined(separator: "\n")
    }
}

/// Static scan for interactive controls without an accessibility identifier.
/// SwiftUI: checks the control's own modifier chain for `.accessibilityIdentifier`.
/// UIKit: a control assigned to a variable must have `<var>.accessibilityIdentifier =` in the file.
/// Interface Builder: control elements without an accessibility identifier.
/// Suppress a finding with `// proof:ignore` on the same line or the line above.
public struct AXScanner {
    public static let swiftUIControls = [
        "Button", "Toggle", "TextField", "SecureField", "TextEditor", "Picker", "Slider", "Stepper",
        "NavigationLink", "Link", "Menu", "DatePicker", "ColorPicker", "PhotosPicker", "ShareLink", "Tab",
    ]
    public static let uiKitControls = [
        "UIButton", "UITextField", "UISwitch", "UISlider", "UISegmentedControl", "UIStepper", "UITextView",
        "UIDatePicker", "UIBarButtonItem",
    ]
    static let ibControls: Set<String> = ["button", "textField", "switch", "slider", "segmentedControl", "stepper", "textView", "datePicker"]
    static let skipDirs: Set<String> = [".git", ".build", "DerivedData", "Pods", "Carthage", "build", "node_modules", ".swiftpm", "Tuist"]

    public var extraControls: [String] = []
    public var includeTests = false
    public init(extraControls: [String] = [], includeTests: Bool = false) {
        self.extraControls = extraControls
        self.includeTests = includeTests
    }

    public func scan(paths: [String], root: String) -> AXScanReport {
        var findings: [AXFinding] = []
        var count = 0
        for file in files(paths) {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            count += 1
            let rel = Paths.relative(file, to: root)
            if file.hasSuffix(".swift") { findings += scanSwift(text, file: rel) }
            else { findings += scanInterfaceBuilder(text, file: rel) }
        }
        return AXScanReport(findings: findings, filesScanned: count)
    }

    func files(_ paths: [String]) -> [String] {
        var result: [String] = []
        let fm = FileManager.default
        for path in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue { result.append(path); continue }
            guard let e = fm.enumerator(atPath: path) else { continue }
            while let rel = e.nextObject() as? String {
                let comps = rel.split(separator: "/").map(String.init)
                if comps.contains(where: { Self.skipDirs.contains($0) || $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                    if let last = comps.last, Self.skipDirs.contains(last) || last.hasSuffix(".xcodeproj") || last.hasSuffix(".xcworkspace") { e.skipDescendants() }
                    continue
                }
                if !includeTests, comps.contains(where: { $0.hasSuffix("Tests") || $0.hasSuffix("UITests") }) { continue }
                if rel.hasSuffix(".swift") || rel.hasSuffix(".xib") || rel.hasSuffix(".storyboard") {
                    result.append(Paths.join(path, rel))
                }
            }
        }
        return result.sorted()
    }

    // MARK: - Swift

    public func scanSwift(_ text: String, file: String) -> [AXFinding] {
        let src = SwiftSource(text)
        let previewRanges = previews(src)
        var findings: [AXFinding] = []
        let controls = Set(Self.swiftUIControls + extraControls)
        let m = src.masked
        var i = 0
        while i < m.count {
            guard src.isIdentChar(m[i]), i == 0 || !src.isIdentChar(m[i - 1]) else { i += 1; continue }
            guard let (word, end) = src.identifier(at: i) else { i += 1; continue }
            defer { i = end }
            guard controls.contains(word) || Self.uiKitControls.contains(word) else { continue }
            // Not a member access (.Button), not a declaration (struct Button), not a type annotation.
            if i > 0, m[i - 1] == UInt8(ascii: ".") { continue }
            let prevWord = previousWord(src, before: i)
            if ["struct", "class", "enum", "func", "extension", "typealias", "protocol", "case"].contains(prevWord) { continue }
            let next = src.skipSpace(end)
            guard next < m.count else { continue }
            let opener = m[next]

            if controls.contains(word) {
                guard opener == UInt8(ascii: "(") || opener == UInt8(ascii: "{") else { continue }
                if previewRanges.contains(where: { $0.contains(i) }) { continue }
                let afterCall = src.skipCallTail(end)
                let modifiers = src.modifierChain(afterCall)
                if modifiers.contains("accessibilityIdentifier") { continue }
                let line = src.line(at: i)
                if ignored(src, line) { continue }
                findings.append(AXFinding(file: file, line: line, kind: "swiftui", control: word, snippet: snippet(src, line)))
            } else {
                // UIKit: `let/var name ... = UIButton(...)` / `UIButton.systemButton(...)` / `UIButton(type:)`
                guard opener == UInt8(ascii: "(") || opener == UInt8(ascii: ".") else { continue }
                // `UIButton.systemButton(...)` is a control; `UIButton.Configuration` is a nested type.
                if opener == UInt8(ascii: "."), let (member, _) = src.identifier(at: src.skipSpace(next + 1)),
                   member.first?.isUppercase == true { continue }
                guard let name = assignedName(src, before: i) else { continue }
                let line = src.line(at: i)
                if ignored(src, line) { continue }
                let masked = String(decoding: m, as: UTF8.self)
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*\\.\\s*accessibilityIdentifier\\s*="
                if masked.range(of: pattern, options: .regularExpression) != nil { continue }
                findings.append(AXFinding(file: file, line: line, kind: "uikit", control: word, snippet: snippet(src, line)))
            }
        }
        return findings
    }

    /// Ranges of `#Preview { }` blocks and `PreviewProvider` structs.
    func previews(_ src: SwiftSource) -> [Range<Int>] {
        let text = String(decoding: src.masked, as: UTF8.self)
        var ranges: [Range<Int>] = []
        let patterns = [#"#Preview\b[^{]*\{"#, #"struct\s+\w+\s*:\s*PreviewProvider\s*\{"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            // Masked text is ASCII-compatible byte-for-byte only where the original was ASCII;
            // map via utf8 offsets to stay exact.
            let ns = text as NSString
            for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let endUTF16 = match.range.location + match.range.length
                let prefix = ns.substring(to: endUTF16)
                let braceOffset = prefix.utf8.count - 1
                if let close = src.matching(braceOffset) { ranges.append(braceOffset..<close) }
            }
        }
        return ranges
    }

    func previousWord(_ src: SwiftSource, before i: Int) -> String {
        var k = i - 1
        while k >= 0, src.masked[k] == 32 || src.masked[k] == 9 { k -= 1 }
        let end = k + 1
        while k >= 0, src.isIdentChar(src.masked[k]) { k -= 1 }
        return String(decoding: src.masked[(k + 1)..<end], as: UTF8.self)
    }

    /// For `let name: UIButton = UIButton(...)` or `var name = UIButton(...)` returns "name".
    func assignedName(_ src: SwiftSource, before i: Int) -> String? {
        let lineNo = src.line(at: i)
        let start = src.lineStarts[lineNo - 1]
        let head = String(decoding: src.masked[start..<i], as: UTF8.self)
        guard let r = head.range(of: #"\b(?:let|var)\s+(\w+)\s*(?::[^=]+)?=\s*$"#, options: .regularExpression) else { return nil }
        let decl = String(head[r])
        let parts = decl.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "=" || $0 == "\t" })
        return parts.count >= 2 ? String(parts[1]) : nil
    }

    func ignored(_ src: SwiftSource, _ line: Int) -> Bool {
        let marker = "proof:ignore"
        if src.lineText(line).contains(marker) { return true }
        return line > 1 && src.lineText(line - 1).contains(marker)
    }

    func snippet(_ src: SwiftSource, _ line: Int) -> String {
        let t = src.lineText(line).trimmingCharacters(in: .whitespaces)
        return t.count > 90 ? String(t.prefix(90)) + "…" : t
    }

    // MARK: - Interface Builder

    public func scanInterfaceBuilder(_ text: String, file: String) -> [AXFinding] {
        let delegate = IBDelegate(controls: Self.ibControls)
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = delegate
        delegate.parser = parser
        _ = parser.parse()
        return delegate.missing.map {
            AXFinding(file: file, line: $0.line, kind: "ib", control: $0.type, snippet: "<\($0.type)\($0.title.map { " \"\($0)\"" } ?? "")>")
        }
    }
}

final class IBDelegate: NSObject, XMLParserDelegate {
    struct Open { let type: String; let line: Int; var title: String?; var hasId: Bool }
    let controls: Set<String>
    weak var parser: XMLParser?
    var stack: [Open?] = []
    var missing: [Open] = []

    init(controls: Set<String>) { self.controls = controls }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if controls.contains(name) {
            stack.append(Open(type: name, line: parser.lineNumber, title: attributes["title"] ?? attributes["placeholder"] ?? attributes["text"], hasId: false))
            return
        }
        // <accessibility key="accessibilityConfiguration" identifier="login.button"/>
        if name == "accessibility", let id = attributes["identifier"], !id.isEmpty,
           let idx = stack.lastIndex(where: { $0 != nil }) {
            stack[idx]?.hasId = true
        }
        // <state key="normal" title="Log in"/> gives buttons their title.
        if name == "state", let title = attributes["title"], let idx = stack.lastIndex(where: { $0 != nil }), stack[idx]?.title == nil {
            stack[idx]?.title = title
        }
        stack.append(nil)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let last = stack.popLast() else { return }
        if let open = last, !open.hasId { missing.append(open) }
    }
}
