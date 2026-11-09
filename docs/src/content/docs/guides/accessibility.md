---
title: Accessibility identifiers
description: Find controls without identifiers, and run Xcode's accessibility audit on screen.
---

proof finds elements most reliably by **accessibility identifier** (`#login.submit`). Labels change
with copy and localization; identifiers don't.

## In your code

```sh
proof ax scan                                         # SwiftUI, UIKit and xib/storyboard controls without identifiers
proof ax scan Modules/Login                           # one folder
proof ax scan Modules/Login --control PrimaryButton   # include your custom controls
```

Silence a deliberate case with `// proof:ignore` on the line, or the line above.

## On screen

```sh
proof ui tree --missing-ids
proof ax audit                       # Xcode's accessibility audit + controls without identifiers
proof ax audit --only contrast       # one kind of issue
proof ax audit --strict              # exit 1 when anything is found
```

```
AX AUDIT · 3 issues
hit-region        button #presets.add "Add preset"  Hit area is too small
contrast          text "Last used"  Contrast failed
dynamic-type      text "25:00"  Dynamic Type font sizes are unsupported
```

`proof ax audit` runs Xcode's accessibility audit (`performAccessibilityAudit`) on the current screen:
contrast, hit regions, missing descriptions, Dynamic Type, clipped text and traits. It needs an iOS 17 or
newer simulator; on older ones only identifiers are checked. Combine it with
[variants](../snaps/#dark-mode-text-sizes-and-languages) to audit dark mode and large text too.

## Naming

Use `<feature>.<element>`, for example `login.submit` or `timer.presets`.
