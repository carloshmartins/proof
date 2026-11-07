---
title: The report
description: One page with the build, tests and screenshots for a reviewer.
---

```sh
proof packet           # write the report for this branch
proof packet --open    # and open the HTML page
```

`proof packet` collects everything this branch produced:

- the last build and test results,
- the stack results, if you ran `proof test --stack`,
- accessibility findings from `proof ax scan`,
- every snap, with the screenshot on the other branch next to it and the tree diff.

![The proof report](/proof/media/report.png)

It writes `report.md` and `report.html` in `~/.proof/sessions/<repo>/<branch>/`. Nothing is uploaded
anywhere: share the file or paste the Markdown into a PR yourself.
