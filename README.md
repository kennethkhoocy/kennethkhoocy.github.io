# kennethkhoocy.github.io

Personal academic website of Kenneth Khoo, Assistant Professor at the NUS Faculty of Law.
Built with [Astro](https://astro.build) and [Tailwind CSS](https://tailwindcss.com), and
deployed to GitHub Pages.

Live at <https://kennethkhoocy.github.io>.

## Local development

Requires [Node.js](https://nodejs.org) 20 or newer.

```bash
npm install      # install dependencies
npm run dev      # start the dev server at http://localhost:4321
npm run build    # build the static site into dist/
npm run preview  # preview the production build locally
```

## Project structure

```
src/
├── pages/        # routes (index, research, publications, teaching, software, media, about, cv)
├── layouts/      # BaseLayout shared by every page
├── components/   # Header, Footer, and reusable pieces
├── content/      # site content as data files (see below)
├── styles/       # global.css (Tailwind + theme variables)
└── content.config.ts   # content collection schemas
```

## Editing content

Most updates are edits to data files under `src/content/`, validated against the schemas in
`src/content.config.ts`:

- `publications/*.yml` — one file per publication.
- `teaching/*.md` — one file per course. The downloadable materials list on each course page
  is fetched at build time from the [`kennethkhoocy/teaching`](https://github.com/kennethkhoocy/teaching)
  repository (folder set by `materials_path`).
- `software/*.yml` — one file per software project, each linking to its repository.
- `media/*.yml` — media mentions.

Pages and layout live in `src/pages/`, `src/layouts/`, and `src/components/`.

## Deployment

Pushing to the `master` branch triggers the GitHub Actions workflow
(`.github/workflows/deploy.yml`), which builds the site and publishes `dist/` to the
`gh-pages` branch that GitHub Pages serves. No manual deploy step is needed.

## License

Code is released under the MIT License (see [LICENSE](LICENSE)). Site content
(text, publications, course materials) is © Kenneth Khoo.
