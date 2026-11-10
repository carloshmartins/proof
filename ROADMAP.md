# Roadmap

Where proof goes next. Nothing here is promised or scheduled. If one of these would help you, say so in an
[issue](https://github.com/carloshmartins/proof/issues/new/choose): that's how the order changes. Pull
requests are welcome too; open an issue first for the bigger ones.

Size: **S** a few days, **M** a week or two.

## Next

- **React Native and Flutter.** They run on the simulator and expose an accessibility tree, so they should
  work today: test them on real apps and document the setup. **S**
- **Variants and devices with `--stack`.** `proof flow run --variants` and `--devices` work on one branch;
  run them on every branch of a stack too. **S**

## Done

Shipped, and described in the [changelog](CHANGELOG.md): simulator state (`open`, `push`, `permission`,
`location`), crash reports, new warnings only, flaky tests, the snap matrix (`--variants`, `--devices`),
Xcode's accessibility audit, `proof review`, the skill for more agents, `.xcresult` results, coverage of
changed lines, pixel diff, `proof bisect`, the output budget and bug reports as flows (`proof repro`).
