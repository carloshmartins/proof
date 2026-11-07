# proof docs

The documentation site, built with [Starlight](https://starlight.astro.build) and deployed to
https://carloshmartins.github.io/proof by `.github/workflows/docs.yml` on every merge to `main`.

```sh
cd docs
npm ci
npm run dev       # http://localhost:4321/proof/
npm run build     # static site in dist/
```

Pages are Markdown files in `src/content/docs/`. The sidebar is in `astro.config.mjs`.
