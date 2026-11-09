import XCTest

/// Executes CLI commands against the attached app. Always called on the main thread.
final class CommandHandler {
    private var app: XCUIApplication?
    private var bundleId: String?

    func handle(path: String, body: Data) -> Data {
        let args = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:]
        RunnerTests.lastIssue = nil
        do {
            var result = try dispatch(path, args)
            if let issue = RunnerTests.lastIssue {
                result = ["ok": false, "error": issue]
            } else if result["ok"] == nil {
                result["ok"] = true
            }
            return encode(result)
        } catch {
            return encode(["ok": false, "error": "\(error)"])
        }
    }

    private func dispatch(_ path: String, _ a: [String: Any]) throws -> [String: Any] {
        switch path {
        case "/launch": return try launch(a)
        case "/activate": return try activate(a)
        case "/terminate":
            try requireApp().terminate()
            return [:]
        case "/tree": return try tree(a)
        case "/tap": return try tap(a)
        case "/longpress": return try longPress(a)
        case "/type": return try type(a)
        case "/swipe": return try swipe(a)
        case "/wait": return try wait(a)
        case "/exists":
            let el = try element(a)
            return ["exists": el.exists]
        case "/home":
            XCUIDevice.shared.press(.home)
            return [:]
        case "/alert": return try alert(a)
        case "/audit": return try audit(a)
        default:
            throw RunnerError("unknown command \(path)")
        }
    }

    // MARK: - App lifecycle

    private func launch(_ a: [String: Any]) throws -> [String: Any] {
        guard let id = a["bundleId"] as? String else { throw RunnerError("launch needs bundleId") }
        let app = XCUIApplication(bundleIdentifier: id)
        app.launchArguments = a["arguments"] as? [String] ?? []
        app.launchEnvironment = a["environment"] as? [String: String] ?? [:]
        app.launch()
        self.app = app
        self.bundleId = id
        return ["bundleId": id, "state": stateName(app.state)]
    }

    /// Attaches to an already-running app without relaunching it.
    private func activate(_ a: [String: Any]) throws -> [String: Any] {
        guard let id = (a["bundleId"] as? String) ?? bundleId else { throw RunnerError("activate needs bundleId") }
        let app = XCUIApplication(bundleIdentifier: id)
        app.activate()
        self.app = app
        self.bundleId = id
        return ["bundleId": id, "state": stateName(app.state)]
    }

    private func requireApp() throws -> XCUIApplication {
        guard let app else { throw RunnerError("no app attached. Run: proof ui launch") }
        return app
    }

    // MARK: - Accessibility audit

    /// Xcode's accessibility audit (iOS 17+) on the current screen. Every issue is collected and ignored,
    /// so the audit never records a test failure in the serving loop.
    private func audit(_ a: [String: Any]) throws -> [String: Any] {
        let app = try requireApp()
        guard #available(iOS 17.0, *) else { return ["supported": false, "issues": [Any]()] }
        var issues: [[String: Any]] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            var d: [String: Any] = ["type": Self.auditTypeName(issue.auditType),
                                    "summary": issue.compactDescription,
                                    "detail": issue.detailedDescription]
            if let el = issue.element, el.exists {
                let f = el.frame
                d["element"] = ["type": typeName(el.elementType), "id": el.identifier, "label": el.label,
                                "frame": [Int(f.minX), Int(f.minY), Int(f.width), Int(f.height)]] as [String: Any]
            }
            issues.append(d)
            return true
        }
        return ["supported": true, "issues": issues]
    }

    @available(iOS 17.0, *)
    private static func auditTypeName(_ t: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element-detection"), (.hitRegion, "hit-region"),
            (.sufficientElementDescription, "description"), (.dynamicType, "dynamic-type"),
            (.textClipped, "text-clipped"), (.trait, "trait"),
        ]
        return names.first { t == $0.0 }?.1 ?? "other"
    }

    // MARK: - Tree

    private func tree(_ a: [String: Any]) throws -> [String: Any] {
        let app = try requireApp()
        let maxNodes = a["maxNodes"] as? Int ?? 1500
        let snapshot = try app.snapshot()
        var nodes: [[String: Any]] = []
        func walk(_ s: XCUIElementSnapshot, depth: Int) {
            guard nodes.count < maxNodes else { return }
            let label = s.label
            let id = s.identifier
            let value = (s.value as? String) ?? (s.value as? NSNumber)?.stringValue ?? ""
            let placeholder = s.placeholderValue ?? ""
            let keep = s.elementType != .other || !id.isEmpty || !label.isEmpty
            var childDepth = depth
            if keep {
                let f = s.frame
                var node: [String: Any] = [
                    "type": typeName(s.elementType),
                    "depth": depth,
                    "frame": [Int(f.origin.x), Int(f.origin.y), Int(f.size.width), Int(f.size.height)],
                ]
                if !id.isEmpty { node["id"] = id }
                if !label.isEmpty { node["label"] = label }
                if !value.isEmpty { node["value"] = value }
                if !placeholder.isEmpty { node["placeholder"] = placeholder }
                if !s.isEnabled { node["enabled"] = false }
                if s.isSelected { node["selected"] = true }
                nodes.append(node)
                childDepth = depth + 1
            }
            for child in s.children { walk(child, depth: childDepth) }
        }
        walk(snapshot, depth: 0)
        return ["nodes": nodes, "truncated": nodes.count >= maxNodes, "screen": screen(app)]
    }

    // MARK: - Interaction

    private func tap(_ a: [String: Any]) throws -> [String: Any] {
        let app = try requireApp()
        if let x = a["x"] as? Double, let y = a["y"] as? Double {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
            return ["target": ["type": "point", "frame": [Int(x) - 22, Int(y) - 22, 44, 44]], "screen": screen(app)]
        }
        let el = try existing(a)
        let info = target(el)
        // Describe before tapping: a tap that navigates removes the element, and resolving it afterwards fails.
        let tapped = describe(el)
        if el.isHittable { el.tap() }
        else {
            // A coordinate tap on an element under the keyboard lands on a key or a QuickType suggestion.
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.contains(CGPoint(x: el.frame.midX, y: el.frame.midY)) {
                throw RunnerError("\(tapped) is covered by the keyboard. Dismiss it first, e.g. tap the return key")
            }
            el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        return ["tapped": tapped, "target": info, "screen": screen(app)]
    }

    private func longPress(_ a: [String: Any]) throws -> [String: Any] {
        let el = try existing(a)
        let info = target(el)
        let pressed = describe(el)
        el.press(forDuration: a["duration"] as? Double ?? 1.0)
        return ["pressed": pressed, "target": info, "screen": screen(try requireApp())]
    }

    private func type(_ a: [String: Any]) throws -> [String: Any] {
        let app = try requireApp()
        guard let text = a["value"] as? String else { throw RunnerError("type needs a value") }
        var target: XCUIElement = app
        var info: [String: Any]?
        if hasSelector(a) {
            let el = try existing(a)
            info = self.target(el)
            el.tap()
            target = el
        }
        if a["clear"] as? Bool == true, let current = target.value as? String, !current.isEmpty {
            target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        target.typeText(text)
        if a["submit"] as? Bool == true { target.typeText("\n") }
        guard let info else { return [:] }
        return ["target": info, "screen": screen(app)]
    }

    private func swipe(_ a: [String: Any]) throws -> [String: Any] {
        let app = try requireApp()
        let target = hasSelector(a) ? try existing(a) : app
        let info = hasSelector(a) ? self.target(target) : nil
        switch (a["direction"] as? String ?? "up").lowercased() {
        case "up": target.swipeUp()
        case "down": target.swipeDown()
        case "left": target.swipeLeft()
        case "right": target.swipeRight()
        default: throw RunnerError("direction must be up/down/left/right")
        }
        guard let info else { return [:] }
        return ["target": info, "screen": screen(app)]
    }

    private func wait(_ a: [String: Any]) throws -> [String: Any] {
        let el = try element(a)
        let timeout = a["timeout"] as? Double ?? 10
        if a["gone"] as? Bool == true {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: el)
            let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
            return ["ok": result == .completed, "gone": result == .completed]
        }
        let found = el.waitForExistence(timeout: timeout)
        guard found else { return ["ok": false, "exists": false] }
        return ["ok": true, "exists": true, "target": target(el), "screen": screen(try requireApp())]
    }

    private func alert(_ a: [String: Any]) throws -> [String: Any] {
        // System alerts (permissions) live in SpringBoard; in-app alerts in the app.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let candidates = [app?.alerts.firstMatch, springboard.alerts.firstMatch].compactMap { $0 }
        guard let alert = candidates.first(where: { $0.waitForExistence(timeout: a["timeout"] as? Double ?? 3) }) else {
            throw RunnerError("no alert visible")
        }
        let buttons = alert.buttons
        let wanted = a["button"] as? String
        let action = (a["action"] as? String ?? "accept").lowercased()
        let button: XCUIElement
        if let wanted { button = buttons[wanted] }
        else if action == "dismiss" { button = buttons.element(boundBy: 0) }
        else { button = buttons.element(boundBy: max(0, buttons.count - 1)) }
        guard button.exists else { throw RunnerError("alert button not found: \(wanted ?? action)") }
        let label = button.label
        button.tap()
        return ["alert": alert.label, "tapped": label]
    }

    // MARK: - Element lookup

    private func hasSelector(_ a: [String: Any]) -> Bool {
        a["id"] != nil || a["label"] != nil || a["text"] != nil || a["type"] != nil
    }

    /// Selector keys: id (exact identifier), label (exact), text (contains, case-insensitive,
    /// in label or identifier), type (element type name), index (nth match).
    private func element(_ a: [String: Any]) throws -> XCUIElement {
        let app = try requireApp()
        let type = (a["type"] as? String).flatMap(elementType(named:)) ?? .any
        var query = app.descendants(matching: type)
        if let id = a["id"] as? String { query = query.matching(NSPredicate(format: "identifier == %@", id)) }
        if let label = a["label"] as? String { query = query.matching(NSPredicate(format: "label == %@", label)) }
        if let text = a["text"] as? String {
            query = query.matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", text, text))
        }
        let index = a["index"] as? Int ?? 0
        return index == 0 ? query.firstMatch : query.element(boundBy: index)
    }

    private func existing(_ a: [String: Any]) throws -> XCUIElement {
        let el = try element(a)
        guard el.waitForExistence(timeout: a["timeout"] as? Double ?? 5) else {
            throw RunnerError("element not found: \(selectorDescription(a)). Run `proof ui tree` to see what is on screen")
        }
        return el
    }

    private func selectorDescription(_ a: [String: Any]) -> String {
        ["type", "id", "label", "text", "index"].compactMap { k in a[k].map { "\(k)=\($0)" } }.joined(separator: " ")
    }

    /// The acted element for the CLI's step events: type, id, label and frame in points.
    private func target(_ el: XCUIElement) -> [String: Any] {
        let f = el.frame
        var t: [String: Any] = ["type": typeName(el.elementType),
                                "frame": [Int(f.origin.x), Int(f.origin.y), Int(f.size.width), Int(f.size.height)]]
        if !el.identifier.isEmpty { t["id"] = el.identifier }
        if !el.label.isEmpty { t["label"] = el.label }
        return t
    }

    /// The app's frame in points, so screenshots map to element frames.
    private func screen(_ app: XCUIApplication) -> [String: Any] {
        let f = app.frame
        return ["width": Int(f.size.width), "height": Int(f.size.height)]
    }

    private func describe(_ el: XCUIElement) -> String {
        let id = el.identifier, label = el.label
        return "\(typeName(el.elementType))" + (id.isEmpty ? "" : " #\(id)") + (label.isEmpty ? "" : " \"\(label)\"")
    }

    private func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data(#"{"ok":false,"error":"encode failed"}"#.utf8)
    }

    private func stateName(_ s: XCUIApplication.State) -> String {
        switch s {
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "suspended"
        case .runningBackground: return "background"
        case .runningForeground: return "foreground"
        default: return "unknown"
        }
    }
}

// MARK: - Element type names

private let typeNames: [XCUIElement.ElementType: String] = [
    .any: "any", .other: "other", .application: "app", .window: "window", .alert: "alert",
    .button: "button", .navigationBar: "navbar", .tabBar: "tabbar", .tab: "tab", .toolbar: "toolbar",
    .staticText: "text", .textField: "textfield", .secureTextField: "securefield", .searchField: "searchfield",
    .textView: "textview", .image: "image", .icon: "icon", .cell: "cell", .table: "table",
    .collectionView: "collection", .scrollView: "scroll", .switch: "switch", .toggle: "toggle",
    .slider: "slider", .stepper: "stepper", .picker: "picker", .pickerWheel: "pickerwheel",
    .segmentedControl: "segmented", .link: "link", .map: "map", .webView: "webview",
    .keyboard: "keyboard", .key: "key", .sheet: "sheet", .menu: "menu", .menuItem: "menuitem",
    .datePicker: "datepicker", .pageIndicator: "pageindicator", .activityIndicator: "spinner",
    .progressIndicator: "progress", .group: "group", .scrollBar: "scrollbar", .statusBar: "statusbar",
]

private let namesToType: [String: XCUIElement.ElementType] =
    Dictionary(typeNames.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })

func typeName(_ t: XCUIElement.ElementType) -> String { typeNames[t] ?? "t\(t.rawValue)" }
func elementType(named name: String) -> XCUIElement.ElementType? { namesToType[name.lowercased()] }
