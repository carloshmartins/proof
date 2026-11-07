---
title: Accessibility identifiers
description: Find controls without identifiers, in code and on screen.
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
```

## Naming

Use `<feature>.<element>`, for example `login.submit` or `timer.presets`.
