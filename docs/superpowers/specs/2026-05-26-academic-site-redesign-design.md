# Academic Site Redesign — Design Spec

**Date:** 2026-05-26
**Author:** Kenneth Khoo (with Claude)
**Repo:** `kennethkhoocy/kennethkhoocy.github.io`
**Live URL:** https://kennethkhoocy.github.io/

## 1. Background and goals

The current site is built on the Academic Pages Jekyll template (a fork of minimal-mistakes). It contains 16 publications, 3 teaching entries, an author profile sidebar, and a homepage with a long bio plus three featured papers. The site works, but Kenneth wants to redesign it for three reasons, in order of priority:

1. **Aesthetic.** The minimal-mistakes look feels dated and generic.
2. **Stack.** Moving off Jekyll for a modern toolchain with better DX and fewer template-locked styling constraints.
3. **Scholarly positioning.** The current layout does not signal Kenneth's profile as an empirical law-and-economics scholar as crisply as it could.

A previous redesign attempt (commit `8bec951`, "Update website for academic theme") was merged and then reverted (`dcf623e`). This spec is the second attempt, with explicit upfront decisions to avoid the same outcome.

## 2. Decisions

| Decision | Choice | Notes |
|---|---|---|
| Aesthetic | Stripe-style minimal | Sans-serif, ample whitespace, restrained palette, single accent color |
| Stack | Astro 5.x + TypeScript + Tailwind v4 | Content collections for typed publications/teaching/news/talks/media |
| Hosting | GitHub Pages, same repo | Source branch flips from `main /` to `gh-pages` post-cutover |
| Domain | `kennethkhoocy.github.io` (no custom domain) | |
| Accent color | Deep navy (`#1E3A8A` light / `#60A5FA` dark) | |
| Dark mode | Auto-detect + manual toggle, persisted in `localStorage` | |
| Paper links | Title links to SSRN abstract page wherever possible | Fallback: PDF link if a file is in the repo; else plain text |
| Per-paper detail pages | None | All paper info lives inline on `/research/` |
| News page | Yes, empty initially | No RSS feed |
| Homepage "Recent" block | Removed | Section left blank below Featured Research |
| Publication grouping | Two groups — Published / Working — chronological within each | Published includes forthcoming; Working covers under-review and working papers |
| Cutover style | Clean cutover on `main`, no parallel preview path | |
| View Transitions | Enabled | Astro's built-in CSS view transitions for smooth nav |

## 3. Information architecture

### Sitemap

```
/                    Home          Bio, photo, contacts, 3 featured papers
/research/           Research      All 16 papers, grouped Published / Working
/teaching/           Teaching      Course list
/teaching/<slug>/    Course page   Syllabus, description, materials
/cv/                 CV            HTML version plus PDF download button
/news/               News          Reverse-chronological updates (empty for now)
/talks/              Talks         Conference presentations, dated
/media/              Media         Press, op-eds, interviews
```

### Header (sticky)
- Left: "Kenneth Khoo" wordmark, links to `/`
- Right: Research · Teaching · CV · News · Talks · Media · 🌓 mode toggle
- Backdrop blur kicks in once the page scrolls past ~16px
- Mobile: nav collapses into a hamburger menu

### Footer (short)
- Inline links: Email · Google Scholar · GitHub · LinkedIn · SSRN
- © 2026 Kenneth Khoo · Built with Astro

### URL preservation
Old URLs from the Jekyll site that must keep working:
- `/about/` and `/about.html` → 301-style redirect to `/`
- `/publications/` → redirect to `/research/`
- `/cv/Kenneth%20Khoo%20CV.pdf` stays at the same path

Since GitHub Pages is static, redirects are implemented as thin HTML pages at the old paths with a `<meta http-equiv="refresh">` and an immediate JS replace.

## 4. Visual system

### Typography
- Body and UI: **Inter** (variable), self-hosted via `@fontsource-variable/inter`
- Headings: Inter, weight 600–700, slightly tighter tracking
- Numerics in tables (years in publication list): **JetBrains Mono** for column alignment
- Body size: 17px desktop, 16px mobile; line-height 1.6; max measure 70ch

### Color tokens

| Token | Light | Dark |
|---|---|---|
| `--bg` | `#FFFFFF` | `#0B0D10` |
| `--surface` | `#FAFAFA` | `#15181D` |
| `--text` | `#0B0D10` | `#F5F5F5` |
| `--text-muted` | `#6B7280` | `#9CA3AF` |
| `--border` | `#E5E7EB` | `#22272E` |
| `--accent` | `#1E3A8A` | `#60A5FA` |
| `--accent-hover` | `#1E40AF` | `#3B82F6` |

Dark mode strategy: `class="dark"` on `<html>`. A ~15-line preflight script in `<head>` reads `localStorage` (falling back to `prefers-color-scheme`) and sets the class before paint to prevent flash.

### Layout
- Max content width: **720px** for text-heavy pages (CV, course pages); **960px** for list pages (Research, Talks, News, Media); homepage uses 960px with the photo right-aligned at the top
- Vertical rhythm: ~6rem between major sections, ~1.5rem between rows in a list
- Sticky header: ~64px tall
- Generous horizontal padding (32px+) on all viewports

### Component patterns
- **PaperRow** — title (link, weight 500) on line 1; meta line ("coauthors · venue · year ★" if awarded) on line 2; thin divider below
- **FeaturedPaper** (homepage only) — larger title, one-sentence `summary`, same meta line
- **Button** — flat, accent border, no shadows
- **ModeToggle** — sun/moon Lucide icon, top-right of header
- **SectionDivider** — `--- heading ---` style horizontal rule with inline label

## 5. Page-by-page

### `/` Home
```
┌─────────────────────────────────────────────────────────┐
│  Kenneth Khoo                              ┌──────────┐ │
│  Assistant Professor                       │  PHOTO   │ │
│  NUS Faculty of Law                        └──────────┘ │
│                                                          │
│  Empirical research on corporate           ✉  🎓  in  📄 │
│  governance, antitrust, and the                          │
│  law-and-economics of financial markets.                │
│                                                          │
│  ─── Featured research ───────────────────────────────   │
│                                                          │
│  Expanding Shareholder Voice                            │
│  with Tallarita · J. Law & Econ. · 2025 ★                │
│  Evidence that SEC's 2021 guidance shift drives the     │
│  decline in support for E&S proposals.                  │
│                                                          │
│  The Price of Delaware Corporate Law Reform             │
│  with Tallarita · under review · 2025                   │
│  Event study showing SB 21 reduced shareholder value.   │
│                                                          │
│  Visual Saliency and Investment Decisions               │
│  with Enriques, Desiato, Lee, Romano · WP · 2025        │
│  Eye-tracking experiment on fee salience and choice.    │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

Hero replaces the heavy author sidebar of the current site. Bio trimmed from the current 5+ sentences to two sentences; the rest of the biographical content (awards, education) moves to the CV page. Three featured papers are selected by setting `featured: true` and `summary: "..."` in their publication entries.

### `/research/`
```
Research

Published
─────────
Expanding Shareholder Voice                          2025
  with Tallarita · J. Law & Econ. (forthcoming) ★

Common Ownership and ESG                              2023
  with [coauthors] · [journal]

[... year desc, alpha within year ...]

Working
───────
The Price of Delaware Corporate Law Reform            2025
  with Tallarita · under review

Visual Saliency and Investment Decisions              2025
  with Enriques, Desiato, Lee, Romano

[...]
```
Each title links to SSRN. Award marker (★) inline. No abstracts on this page; SSRN holds them. No filters or search in v1.

### `/teaching/`
Index lists 3 courses, each one with title, course code if any, and a one-sentence description. Click → `/teaching/<slug>/`. Each course page: course code, semesters taught, syllabus link, description, materials.

### `/cv/`
```
Curriculum Vitae                      [ Download PDF ↓ ]

Kenneth Khoo
Assistant Professor · NUS Faculty of Law
kenneth.khoo@nus.edu.sg

Appointments
────────────
2024–   Assistant Professor, NUS Faculty of Law
2022–23 Program Fellow, Harvard Law Program on Corporate Governance
...

Education
─────────
2024  J.S.D., Yale Law School
2019  LL.M., Yale Law School
2018  M.Sc. Economics, LSE
2014  LL.B. (First Class), B.Soc.Sci. (Economics, First Class), NUS

Publications
────────────
[mirrors /research/, each title → SSRN]

Awards · Talks · Service
[Talks list rendered from the `talks` collection; Awards and Service authored as markdown on this page]
```

CV pulls publication and talk listings from the same content collections as `/research/` and `/talks/` so that updates propagate automatically. Appointments, education, awards, service, and teaching activities are authored as markdown on the CV page directly.

### `/news/`, `/talks/`, `/media/`
Year-grouped reverse-chronological lists.

```
News

2026
────
Apr   New WP: Visual Saliency results posted

2025
────
Nov   SB 21 paper accepted, JLE roundtable
```
- Talks row: `date · venue · paper title (→ SSRN) · [slides]`
- Media row: `date · outlet · "headline" (→ article) · brief note`

All three pages render an empty-state ("No items yet.") gracefully so they can ship with no content.

## 6. Technical architecture

### Repo layout (post-cutover)
```
kennethkhoocy.github.io/
├── docs/superpowers/specs/    This spec lives here
├── src/
│   ├── components/
│   │   ├── Header.astro
│   │   ├── Footer.astro
│   │   ├── ModeToggle.astro
│   │   ├── PaperRow.astro
│   │   ├── FeaturedPaper.astro
│   │   └── SectionDivider.astro
│   ├── content/
│   │   ├── publications/      16 .yml entries
│   │   ├── teaching/           3 .md entries
│   │   ├── news/              empty
│   │   ├── talks/             empty
│   │   └── media/             empty
│   ├── content.config.ts      Zod schemas
│   ├── layouts/BaseLayout.astro
│   ├── pages/
│   │   ├── index.astro
│   │   ├── research.astro
│   │   ├── cv.astro
│   │   ├── news.astro
│   │   ├── talks.astro
│   │   ├── media.astro
│   │   ├── teaching/
│   │   │   ├── index.astro
│   │   │   └── [slug].astro
│   │   ├── about/index.astro     redirect → /
│   │   ├── about.html            redirect → /
│   │   └── publications/index.astro  redirect → /research/
│   └── styles/global.css
├── public/
│   ├── cv/Kenneth Khoo CV.pdf
│   └── images/headshot.jpg
├── .github/workflows/deploy.yml
├── astro.config.mjs
├── tsconfig.json
└── package.json
```

### Content collection schemas

```ts
// src/content.config.ts
import { z, defineCollection } from 'astro:content';

const publications = defineCollection({
  type: 'data',
  schema: z.object({
    title: z.string(),
    year: z.number().int(),
    coauthors: z.array(z.string()).default([]),
    venue: z.string(),
    status: z.enum(['published', 'forthcoming', 'under_review', 'working_paper']),
    ssrn_url: z.string().url().optional(),
    pdf_path: z.string().optional(),
    awards: z.array(z.string()).default([]),
    summary: z.string().optional(),      // shown on home if featured
    featured: z.boolean().default(false),
  }),
});

const teaching = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    code: z.string().optional(),
    semesters: z.array(z.string()).default([]),
    syllabus_url: z.string().url().optional(),
    description: z.string(),
  }),
});

const news = defineCollection({
  type: 'data',
  schema: z.object({
    date: z.date(),
    body: z.string(),
  }),
});

const talks = defineCollection({
  type: 'data',
  schema: z.object({
    date: z.date(),
    venue: z.string(),
    paper_title: z.string(),
    paper_ssrn_url: z.string().url().optional(),
    slides_url: z.string().url().optional(),
  }),
});

const media = defineCollection({
  type: 'data',
  schema: z.object({
    date: z.date(),
    outlet: z.string(),
    headline: z.string(),
    url: z.string().url(),
    note: z.string().optional(),
  }),
});

export const collections = { publications, teaching, news, talks, media };
```

Grouping rule for `/research/`:
- Published group: `status ∈ {published, forthcoming}`
- Working group: `status ∈ {under_review, working_paper}`
- Sort: `year` desc, then `title` asc within each year

### Dark mode

`tailwind.config` uses `darkMode: 'class'`. `BaseLayout.astro` includes a preflight script in `<head>` (before any stylesheet) that runs synchronously:

```html
<script is:inline>
  const stored = localStorage.getItem('theme');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  if (stored === 'dark' || (!stored && prefersDark)) {
    document.documentElement.classList.add('dark');
  }
</script>
```

`ModeToggle.astro` toggles the class and writes `localStorage`.

### View Transitions
Enabled via `<ViewTransitions />` in `BaseLayout.astro`. Provides smooth cross-page fade by default; no per-page customization in v1.

### Deployment
`.github/workflows/deploy.yml` uses `withastro/action@v3`. Trigger: push to `main`. The action builds the site and publishes to the `gh-pages` branch. Repo Settings → Pages: source = `gh-pages` branch, folder = `/`.

`astro.config.mjs`:
```js
import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  site: 'https://kennethkhoocy.github.io',
  base: '/',
  integrations: [tailwind()],
});
```

## 7. Migration plan

Phased execution on a new `astro-rewrite` branch, merged in a single PR at cutover.

| # | Step | Notes |
|---|---|---|
| 1 | Scrape SSRN URLs | Use firecrawl CLI on https://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id=2570590; map abstract URLs to the 16 papers by title; cross-check against `C:\Users\Kenneth\Dropbox\NUS Work\Admin\CV\Github\Kenneth Khoo CV.pdf` |
| 2 | Archive Jekyll files | Move all current top-level Jekyll files (`_config.yml`, `_pages/`, `_publications/`, `_teaching/`, `_layouts/`, `_includes/`, `_sass/`, `_data/`, `_drafts/`, `_portfolio/`, `assets/`, `Gemfile`, `Dockerfile`, `markdown_generator/`, `talkmap.*`, etc.) into `_legacy-jekyll/` on the rewrite branch. Copy `cv/Kenneth Khoo CV.pdf` → `public/cv/Kenneth Khoo CV.pdf` and `images/1760923711828.jpg` → `public/images/headshot.jpg` as part of the new structure |
| 3 | Scaffold Astro app | `npm create astro@latest`, configure Tailwind v4 + content collections |
| 4 | Implement collection schemas | `src/content.config.ts` per §6 |
| 5 | Migrate 16 publications | Write `.yml` entries with SSRN URLs from step 1; mark `featured: true` on the three current featured papers |
| 6 | Migrate 3 teaching entries | Port from existing `_teaching/` markdown |
| 7 | Build components + base layout | Header, Footer, ModeToggle, PaperRow, FeaturedPaper, SectionDivider, BaseLayout |
| 8 | Build pages | index, research, cv, news, talks, media, teaching index + [slug], redirect pages |
| 9 | Wire dark mode preflight + View Transitions | per §6 |
| 10 | Add GH Actions workflow | `withastro/action@v3` → `gh-pages` branch |
| 11 | Smoke test build locally | `npm run build && npx serve dist` |
| 12 | Open PR, merge to `main` | Triggers first deploy |
| 13 | Flip Pages source | Repo Settings → Pages: switch from `main /` to `gh-pages` |
| 14 | Smoke test live site | Desktop and mobile; light and dark; every nav link; SSRN links from `/research/`; redirects from `/about/` and `/publications/` |
| 15 | Delete `_legacy-jekyll/` | Follow-up commit after ~1-week safety window |

## 8. Non-goals (explicit v1 exclusions)

To keep the rewrite focused, the following are intentionally out of scope and may be added later:
- Search across publications
- Topic/keyword filters on `/research/`
- Per-paper detail pages
- RSS feed
- Comments, analytics, third-party trackers
- Multilingual content
- Blog or long-form writing section
- Image gallery or talk video embeds

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| SSRN scrape misses or mismatches a paper | Manual review of generated `.yml` entries against the CV before commit |
| Pages source switch leaves the site briefly broken | Confirm `gh-pages` branch is populated by the Action before flipping the setting |
| Old external links to `/about/` or `/publications/` break | Step 8 builds explicit redirect pages |
| Dark mode flash on first paint | Preflight `is:inline` script in `<head>` sets the class before stylesheets load |
| Reverting requires undoing the Pages source switch | `_legacy-jekyll/` kept for ~1 week so rollback is one `git revert` + one Pages setting change |

## 10. Open questions

None at this time. All decisions resolved in §2.

## 11. Reference data

Authoritative content extracted from Kenneth's CV (the DOCX version is the source of truth per user; PDF used as cross-check) is captured in [`docs/superpowers/reference/2026-05-26-cv-extracted.md`](../reference/2026-05-26-cv-extracted.md). The implementation plan should treat that file as the source of truth for: appointments, education, awards, publication metadata, SSRN URLs (7 of 19 papers plus 1 GitHub-hosted PDF), and the talks/invited-presentations listing. SSRN URLs for the remaining 11 papers are to be sourced via firecrawl scrape of https://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id=2570590 in migration step 1.

The reference file also flags three discrepancies between the current `_publications/` folder and the CV that the migration must fix: a wrong SSRN ID on Visual Saliency, a renamed paper (Controlling Shareholders → Voting Rules and the Price of Peace), and three working papers missing from the existing folder (Singapore Equities Market, Neobrokers, Fork in Boardroom). Post-migration the publications collection should have **19 entries** total.
