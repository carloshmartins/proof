import Foundation

/// A way to look at the same screen: light or dark, a Dynamic Type size, a locale, right-to-left.
/// Written as tokens joined by `+`: `dark`, `ax5`, `ar`, `dark+ax3`, `rtl`. A snap taken under a variant is
/// named `<name>@<variant>`, so it compares with the same variant on another branch.
public struct SnapVariant: Equatable {
    public var name: String
    public var appearance: String? = nil      // light | dark
    public var contentSize: String? = nil     // a `simctl ui content_size` value
    public var locale: String? = nil          // "ar", "pt-BR"
    public var rightToLeft = false

    /// Text sizes by short name, smallest to largest.
    public static let sizes: [(String, String)] = [
        ("xs", "extra-small"), ("s", "small"), ("m", "medium"), ("l", "large"), ("xl", "extra-large"),
        ("xxl", "extra-extra-large"), ("xxxl", "extra-extra-extra-large"),
        ("ax1", "accessibility-medium"), ("ax2", "accessibility-large"), ("ax3", "accessibility-extra-large"),
        ("ax4", "accessibility-extra-extra-large"), ("ax5", "accessibility-extra-extra-extra-large"),
    ]

    /// Locale and right-to-left only apply when the app launches.
    public var needsRelaunch: Bool { locale != nil || rightToLeft }

    public static func parse(_ text: String) throws -> SnapVariant {
        let spec = text.trimmingCharacters(in: .whitespaces)
        guard !spec.isEmpty else { throw ProofError.message("empty variant") }
        var v = SnapVariant(name: spec)
        for token in spec.split(separator: "+").map(String.init) {
            let t = token.trimmingCharacters(in: .whitespaces)
            if t == "light" || t == "dark" {
                guard v.appearance == nil else { throw ProofError.message("variant \(spec): two appearances") }
                v.appearance = t
            } else if let size = sizes.first(where: { $0.0 == t.lowercased() })?.1 {
                guard v.contentSize == nil else { throw ProofError.message("variant \(spec): two text sizes") }
                v.contentSize = size
            } else if t == "rtl" {
                v.rightToLeft = true
            } else if isLocale(t) {
                guard v.locale == nil else { throw ProofError.message("variant \(spec): two locales") }
                v.locale = t
            } else {
                throw ProofError.message("unknown variant '\(t)'. Use light, dark, a text size (\(sizes.map(\.0).joined(separator: ", "))), "
                                         + "a locale like ar or pt-BR, or rtl; join with +, e.g. dark+ax5")
            }
        }
        return v
    }

    /// Comma-separated list, e.g. "dark,ax5,ar".
    public static func parseList(_ text: String?) throws -> [SnapVariant] {
        guard let text else { return [] }
        let variants = try text.split(separator: ",").map { try parse(String($0)) }
        let names = variants.map(\.name)
        guard Set(names).count == names.count else { throw ProofError.message("a variant is listed twice: \(text)") }
        return variants
    }

    static func isLocale(_ t: String) -> Bool {
        let id = t.replacingOccurrences(of: "-", with: "_")
        let language = String(id.split(separator: "_").first ?? "")
        guard language.count >= 2, language.count <= 3, language == language.lowercased() else { return false }
        let known = Set(Locale.availableIdentifiers)
        return known.contains(id) || known.contains(language)
    }

    /// The snap name for `name` under this variant.
    public func snapName(_ name: String) -> String { "\(name)@\(self.name)" }

    /// Launch arguments that apply the locale and writing direction.
    public var launchArguments: [String] {
        var args: [String] = []
        if let locale {
            args += ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale.replacingOccurrences(of: "-", with: "_")]
        }
        if rightToLeft { args += ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"] }
        return args
    }

    /// simctl commands that apply the appearance and text size.
    public func simulatorCommands(udid: String) -> [[String]] {
        var c: [[String]] = []
        if let appearance { c.append(["xcrun", "simctl", "ui", udid, "appearance", appearance]) }
        if let contentSize { c.append(["xcrun", "simctl", "ui", udid, "content_size", contentSize]) }
        return c
    }
}

/// Applies variants to the simulator and puts its appearance and text size back afterwards.
public final class SimulatorLook {
    let udid: String
    private var original: (appearance: String?, size: String?)?

    public init(udid: String) { self.udid = udid }

    /// Applies the variant's appearance and text size; what the variant doesn't set goes back to the
    /// simulator's own (remembered on the first call), so `ax5` after `dark` is not dark.
    /// Waits a moment so the app redraws before a screenshot.
    public func apply(_ v: SnapVariant) throws {
        if original == nil {
            original = (Self.read(udid, "appearance"), Self.read(udid, "content_size"))
        }
        var full = v
        full.appearance = v.appearance ?? original?.appearance
        full.contentSize = v.contentSize ?? original?.size
        let commands = full.simulatorCommands(udid: udid)
        for c in commands { try Shell.checked(c) }
        if !v.simulatorCommands(udid: udid).isEmpty { Thread.sleep(forTimeInterval: 1.2) }
    }

    /// Puts the simulator's appearance and text size back.
    public func restore() {
        guard let original else { return }
        if let a = original.appearance { _ = try? Shell.run(["xcrun", "simctl", "ui", udid, "appearance", a]) }
        if let s = original.size { _ = try? Shell.run(["xcrun", "simctl", "ui", udid, "content_size", s]) }
        self.original = nil
    }

    static func read(_ udid: String, _ setting: String) -> String? {
        guard let r = try? Shell.run(["xcrun", "simctl", "ui", udid, setting]), r.ok else { return nil }
        let value = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.contains(" ") ? nil : value
    }
}
