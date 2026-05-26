# Academic Site Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Jekyll/Academic Pages site at kennethkhoocy.github.io with a new Astro 5 + TypeScript + Tailwind v4 build, Stripe-style minimal aesthetic, navy accent, dark mode, and 19 publications wired to SSRN.

**Architecture:** Static site at repo root. Content lives in typed Astro content collections (publications/teaching/news/talks/media) with Zod schemas. Pages are server-rendered Astro components. Dark mode uses Tailwind's `.dark` class strategy with a `localStorage`-backed preflight script. Cross-page navigation uses Astro's `<ClientRouter />` for view transitions. Deploys via GitHub Actions (modern Pages flow, no `gh-pages` branch).

**Tech Stack:** Astro 5.x, TypeScript, Tailwind CSS v4 (via `@tailwindcss/vite`), `@fontsource-variable/inter`, `@fontsource-variable/jetbrains-mono`, Lucide icon SVGs, `withastro/action@v3` + `actions/deploy-pages@v4`.

**Source materials:**
- Spec: `docs/superpowers/specs/2026-05-26-academic-site-redesign-design.md`
- Reference (publication titles, SSRN URLs, CV facts): `docs/superpowers/reference/2026-05-26-cv-extracted.md`

**Branch:** `astro-rewrite` (already created from `main`, currently has 4 spec/reference commits). Merge to `main` at task 27. Do not push until smoke test passes.

---

## File structure (target, after task 24)

```
kennethkhoocy.github.io/
├── _legacy-jekyll/              # Archived Jekyll files (deleted in task 30)
├── docs/superpowers/            # Specs, reference, plans (untouched)
├── public/
│   ├── cv/Kenneth Khoo CV.pdf
│   ├── cv/Controlling_Shareholders.pdf
│   ├── images/headshot.jpg
│   └── about.html               # /about.html redirect (static)
├── src/
│   ├── components/
│   │   ├── Header.astro
│   │   ├── Footer.astro
│   │   ├── ModeToggle.astro
│   │   ├── PaperRow.astro
│   │   ├── FeaturedPaper.astro
│   │   └── SectionDivider.astro
│   ├── content/
│   │   ├── publications/        # 19 .yml files
│   │   ├── teaching/            # 3 .md files
│   │   ├── news/                # .gitkeep
│   │   ├── talks/               # .gitkeep
│   │   └── media/               # .gitkeep
│   ├── content.config.ts
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
│   │   ├── about/index.astro    # /about/ redirect
│   │   └── publications/index.astro  # /publications/ redirect
│   └── styles/global.css
├── scripts/
│   ├── generate_publications.py # one-shot generator from reference table
│   └── check_links.mjs          # post-build link checker
├── .github/workflows/deploy.yml
├── astro.config.mjs
├── tsconfig.json
└── package.json
```

---

## Phase 1 — Repo preparation

### Task 1: Archive Jekyll files into `_legacy-jekyll/`

**Files:**
- Create: `_legacy-jekyll/` (directory)
- Move into it: every current top-level file/dir except `.git`, `.github`, `docs/`, `LICENSE`, `README.md`

- [ ] **Step 1: Verify you're on `astro-rewrite` branch**

```bash
git branch --show-current
```
Expected: `astro-rewrite`

- [ ] **Step 2: Create the legacy folder and move files in**

Run from repo root:
```bash
mkdir _legacy-jekyll
git mv _config.yml _data _drafts _includes _layouts _pages _portfolio _publications _sass _teaching assets cv images markdown_generator talkmap talkmap.ipynb talkmap.py CONTRIBUTING.md Dockerfile Gemfile package.json _legacy-jekyll/
```

If `git mv` complains about any path not existing, drop that path from the command and re-run. Check with `ls` first if unsure.

- [ ] **Step 3: Verify the only top-level entries left are `_legacy-jekyll/`, `docs/`, `.github/`, `.git/`, `LICENSE`, `README.md`**

```bash
ls -A
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Archive Jekyll files into _legacy-jekyll/ ahead of Astro rewrite"
```

### Task 2: Initialize Astro 5 + TypeScript at repo root

**Files:**
- Create: `package.json`, `astro.config.mjs`, `tsconfig.json`, `src/pages/index.astro` (temporary placeholder), `.gitignore`

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "kennethkhoocy-github-io",
  "type": "module",
  "version": "0.1.0",
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview",
    "astro": "astro",
    "check": "astro check"
  },
  "dependencies": {
    "astro": "^5.0.0"
  },
  "devDependencies": {
    "@astrojs/check": "^0.9.0",
    "typescript": "^5.4.0"
  }
}
```

- [ ] **Step 2: Write `astro.config.mjs`**

```js
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://kennethkhoocy.github.io',
  base: '/',
  trailingSlash: 'always',
});
```

- [ ] **Step 3: Write `tsconfig.json`**

```json
{
  "extends": "astro/tsconfigs/strict",
  "include": ["src/**/*", ".astro/types.d.ts"],
  "exclude": ["dist", "_legacy-jekyll"]
}
```

- [ ] **Step 4: Write `.gitignore`**

```
node_modules/
dist/
.astro/
.DS_Store
*.log
.env
.env.production
```

- [ ] **Step 5: Write a placeholder `src/pages/index.astro`**

```astro
---
---
<html><head><title>placeholder</title></head><body>placeholder</body></html>
```

- [ ] **Step 6: Install and verify build**

```bash
npm install
npx astro check
npm run build
```
Expected: build outputs to `dist/` with no errors. `dist/index.html` exists.

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json astro.config.mjs tsconfig.json .gitignore src/pages/index.astro
git commit -m "Scaffold Astro 5 + TypeScript at repo root"
```

### Task 3: Install Tailwind v4, fonts, and Lucide icons

**Files:**
- Modify: `package.json`, `astro.config.mjs`

- [ ] **Step 1: Install packages**

```bash
npm install tailwindcss @tailwindcss/vite @fontsource-variable/inter @fontsource-variable/jetbrains-mono
npm install -D @types/node
```

- [ ] **Step 2: Update `astro.config.mjs` to register the Tailwind v4 Vite plugin**

```js
import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://kennethkhoocy.github.io',
  base: '/',
  trailingSlash: 'always',
  vite: {
    plugins: [tailwindcss()],
  },
});
```

- [ ] **Step 3: Verify build still passes**

```bash
npm run build
```

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json astro.config.mjs
git commit -m "Add Tailwind v4 (@tailwindcss/vite), Inter + JetBrains Mono fonts"
```

### Task 4: Write `src/styles/global.css` with Tailwind import + color tokens + font setup

**Files:**
- Create: `src/styles/global.css`

- [ ] **Step 1: Write the global stylesheet**

```css
@import "tailwindcss";
@import "@fontsource-variable/inter";
@import "@fontsource-variable/jetbrains-mono";

@variant dark (&:where(.dark, .dark *));

@theme {
  --color-bg: #FFFFFF;
  --color-surface: #FAFAFA;
  --color-text: #0B0D10;
  --color-text-muted: #6B7280;
  --color-border: #E5E7EB;
  --color-accent: #1E3A8A;
  --color-accent-hover: #1E40AF;

  --font-sans: "Inter Variable", ui-sans-serif, system-ui, sans-serif;
  --font-mono: "JetBrains Mono Variable", ui-monospace, monospace;
}

:root {
  color-scheme: light;
}

:root.dark {
  color-scheme: dark;
  --color-bg: #0B0D10;
  --color-surface: #15181D;
  --color-text: #F5F5F5;
  --color-text-muted: #9CA3AF;
  --color-border: #22272E;
  --color-accent: #60A5FA;
  --color-accent-hover: #3B82F6;
}

html {
  background: var(--color-bg);
  color: var(--color-text);
  font-family: var(--font-sans);
  font-size: 17px;
  line-height: 1.6;
}

@media (max-width: 640px) {
  html { font-size: 16px; }
}

a { color: var(--color-accent); text-decoration: none; }
a:hover { color: var(--color-accent-hover); text-decoration: underline; }

.font-mono { font-family: var(--font-mono); }
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/styles/global.css
git commit -m "Add global stylesheet with color tokens, dark mode variant, fonts"
```

---

## Phase 2 — Content collections

### Task 5: Define content collection schemas in `src/content.config.ts`

**Files:**
- Create: `src/content.config.ts`

- [ ] **Step 1: Write the schemas**

```ts
import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const publications = defineCollection({
  loader: glob({ pattern: '**/*.yml', base: './src/content/publications' }),
  schema: z.object({
    title: z.string(),
    year: z.number().int(),
    coauthors: z.array(z.string()).default([]),
    venue: z.string(),
    status: z.enum(['published', 'forthcoming', 'under_review', 'working_paper']),
    ssrn_url: z.string().url().optional(),
    pdf_url: z.string().url().optional(),
    awards: z.array(z.string()).default([]),
    summary: z.string().optional(),
    featured: z.boolean().default(false),
    sort_key: z.number().int().optional(),
  }),
});

const teaching = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/teaching' }),
  schema: z.object({
    title: z.string(),
    code: z.string().optional(),
    semesters: z.array(z.string()).default([]),
    syllabus_url: z.string().url().optional(),
    description: z.string(),
  }),
});

const news = defineCollection({
  loader: glob({ pattern: '**/*.yml', base: './src/content/news' }),
  schema: z.object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    body: z.string(),
  }),
});

const talks = defineCollection({
  loader: glob({ pattern: '**/*.yml', base: './src/content/talks' }),
  schema: z.object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    venue: z.string(),
    paper_title: z.string(),
    paper_ssrn_url: z.string().url().optional(),
    slides_url: z.string().url().optional(),
  }),
});

const media = defineCollection({
  loader: glob({ pattern: '**/*.yml', base: './src/content/media' }),
  schema: z.object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    outlet: z.string(),
    headline: z.string(),
    url: z.string().url(),
    note: z.string().optional(),
  }),
});

export const collections = { publications, teaching, news, talks, media };
```

- [ ] **Step 2: Verify type check passes (collections may report empty)**

```bash
npx astro check
```
Expected: no schema errors. (Collections will have 0 entries until tasks 6-9.)

- [ ] **Step 3: Commit**

```bash
git add src/content.config.ts
git commit -m "Define Zod content collection schemas for publications, teaching, news, talks, media"
```

### Task 6: Create publication YAML files (19 entries)

**Files:**
- Create: `src/content/publications/*.yml` (19 files)

- [ ] **Step 1: Create the publications directory**

```bash
mkdir -p src/content/publications
```

- [ ] **Step 2: Write `01-regulating-inferential-process.yml`**

```yaml
title: "Regulating the Inferential Process in Alleged Article 101 TFEU Infringements"
year: 2017
coauthors: []
venue: "Journal of Competition Law & Economics 13(1):45–88"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2808824"
sort_key: 2017001
```

- [ ] **Step 3: Write `02-singapore-competition-regime.yml`**

```yaml
title: "Singapore's Competition Regime and its Objectives: The Case Against Formalism"
year: 2019
coauthors: ["Allen Sng"]
venue: "Singapore Journal of Legal Studies 1:67–107"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3763649"
sort_key: 2019001
```

- [ ] **Step 4: Write `03-quasi-per-se-rules.yml`**

```yaml
title: "The Inefficiency of Quasi-Per Se Rules: Regulating Information Exchange in EU and US Antitrust Law"
year: 2020
coauthors: ["Jerrold Soh"]
venue: "American Business Law Journal 57(1):45–111"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3498616"
sort_key: 2020001
```

- [ ] **Step 5: Write `04-facilitating-optimal-mechanism.yml`**

```yaml
title: "Facilitating the Optimal Mechanism in Mergers & Acquisitions: A Comparative Perspective from the Commonwealth and United States"
year: 2020
coauthors: ["Hans Tjio"]
venue: "Journal of Indian Law and Society 11(2):108–139"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3548402"
sort_key: 2020002
```

- [ ] **Step 6: Write `05-uber-grab.yml`**

```yaml
title: "Anticompetitive Mergers in Two-Sided Digital Platform Markets: The Case of Uber-Grab"
year: 2021
coauthors: []
venue: "Singapore Academy of Law Journal 33:202–240"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3712823"
sort_key: 2021001
```

- [ ] **Step 7: Write `06-transaction-costs-common-ownership.yml`**

```yaml
title: "Transaction Costs in Common Ownership"
year: 2023
coauthors: []
venue: "University of Pennsylvania Journal of Business Law 25(1):209–294"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4067883"
sort_key: 2023001
```

- [ ] **Step 8: Write `07-gender-gaps-legal-education.yml`**

```yaml
title: "Gender Gaps in Legal Education: The Impact of Class Participation Assessments"
year: 2023
coauthors: ["Jaclyn Neo"]
venue: "Journal of Empirical Legal Studies 20(4):1070–1137"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4227446"
sort_key: 2023002
```

- [ ] **Step 9: Write `08-samr-alibaba.yml`**

```yaml
title: "The Impact of Antitrust Enforcement on China's Digital Platforms: Evidence from SAMR v. Alibaba"
year: 2025
coauthors: ["Sinchit Lai", "Chuyue Tian"]
venue: "International Review of Law & Economics 83, Article 106268"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4850728"
sort_key: 2025001
```

- [ ] **Step 10: Write `09-shareholder-democracy.yml`**

```yaml
title: "The Law and Economics of Shareholder Democracy"
year: 2025
coauthors: []
venue: "European Business Organization Law Review (forthcoming)"
status: forthcoming
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5138536"
sort_key: 2025002
```

- [ ] **Step 11: Write `10-expanding-shareholder-voice.yml`**

```yaml
title: "Expanding Shareholder Voice: The Impact of SEC Guidance on Environmental and Social Proposals"
year: 2025
coauthors: ["Roberto Tallarita"]
venue: "Journal of Law and Economics (forthcoming)"
status: forthcoming
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4913660"
awards:
  - "Best Academic Paper (Junior Category), 2024 Berkeley-ECGI Forum on Corporate Governance"
  - "Best Paper Award for Junior Scholars, Asian Law and Economics Association 2025 Annual Conference"
featured: true
summary: "Evidence that the SEC's 2021 guidance shift drives the decline in support for E&S proposals."
sort_key: 2025003
```

- [ ] **Step 12: Write `11-common-ownership-corporate-sustainability.yml`**

```yaml
title: "Common Ownership and Corporate Sustainability: Evidence from S&P 500 Firms"
year: 2023
coauthors: []
venue: "Book chapter in *Investment Management, Stewardship and Sustainability* (Hart Publishing 2023, eds. Iris Chiu & Hans Christoph Hirt), pp. 235–284"
status: published
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4915568"
sort_key: 2023003
```

- [ ] **Step 13: Write `12-price-of-delaware.yml`**

```yaml
title: "The Price of Delaware Law Reform"
year: 2025
coauthors: ["Roberto Tallarita"]
venue: "Under Review"
status: under_review
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5318203"
featured: true
summary: "Event study showing SB 21 reduced shareholder value at Delaware corporations."
sort_key: 2025010
```

- [ ] **Step 14: Write `13-visual-salience-regulations.yml`**

```yaml
title: "Visual Salience-Based Regulations and Investment Decisions"
year: 2025
coauthors: ["Alessandro Romano", "Yoon-Ho Alex Lee", "Luca Enriques", "Alfredo Desiato"]
venue: "Working Paper"
status: working_paper
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5290238"
featured: true
summary: "Eye-tracking experiment on fee salience and investor choice across mutual funds."
sort_key: 2025011
```

- [ ] **Step 15: Write `14-reflective-loss.yml`**

```yaml
title: "Reflecting on Reflective Loss"
year: 2025
coauthors: []
venue: "Working Paper"
status: working_paper
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5845363"
sort_key: 2025012
```

- [ ] **Step 16: Write `15-voting-rules-price-of-peace.yml`**

```yaml
title: "Voting Rules and the Price of Peace"
year: 2025
coauthors: []
venue: "Working Paper"
status: working_paper
pdf_url: "https://kennethkhoocy.github.io/cv/Controlling_Shareholders.pdf"
sort_key: 2025013
```

- [ ] **Step 17: Write `16-regulatory-intermediation-gap.yml`**

```yaml
title: "The Regulatory Intermediation Gap: Evidence from Singapore's Equity Market Reform"
year: 2026
coauthors: ["Hans Tjio"]
venue: "Working Paper (NUS Law Working Paper No. 2026/004)"
status: working_paper
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6475958"
sort_key: 2026001
```

- [ ] **Step 18: Write `17-neobrokers.yml`**

```yaml
title: "New Disclosure Obligations for Neobrokers"
year: 2026
coauthors: ["Alessandro Romano", "Luca Enriques"]
venue: "Working Paper"
status: working_paper
sort_key: 2026002
```

- [ ] **Step 19: Write `18-fork-in-boardroom.yml`**

```yaml
title: "The Fork in the Boardroom: Market Efficiency, Political Signaling, and the Specialist Director in China"
year: 2026
coauthors: ["Lin Lin"]
venue: "Working Paper"
status: working_paper
sort_key: 2026003
```

- [ ] **Step 20: Write `19-common-ownership-markups.yml`**

```yaml
title: "Common Ownership, Markups and Corporate Governance"
year: 2024
coauthors: []
venue: "Working Paper"
status: working_paper
ssrn_url: "https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4864154"
sort_key: 2024001
```

- [ ] **Step 21: Verify all 19 entries pass schema validation**

```bash
npx astro check
ls src/content/publications/ | wc -l
```
Expected: `astro check` passes; entry count is 19.

- [ ] **Step 22: Commit**

```bash
git add src/content/publications/
git commit -m "Add 19 publication entries with SSRN URLs from CV reference map"
```

### Task 7: Create 3 teaching markdown entries

**Files:**
- Create: `src/content/teaching/company-law.md`, `corporate-law-and-economics.md`, `advanced-corporate-finance.md`

- [ ] **Step 1: Read existing teaching content from legacy**

```bash
cat _legacy-jekyll/_teaching/company-law.md
cat _legacy-jekyll/_teaching/corporate-law-and-economics.md
cat _legacy-jekyll/_teaching/advanced-corporate-finance.md
```
The entries below contain reasonable defaults reconstructed from Kenneth's CV. Cross-check the course codes, semesters, descriptions, and any syllabus links against the legacy files and update inline before committing if the legacy files have more accurate or detailed information.

- [ ] **Step 2: Write `src/content/teaching/company-law.md`**

```markdown
---
title: "Company Law"
code: "LL4030 / LL5030"
semesters: ["AY 2024/25 Sem 1", "AY 2025/26 Sem 1"]
description: "Core company law course covering directors' duties, shareholder rights, capital structure, and corporate insolvency, taught from a law-and-economics perspective."
---

Course materials, slides, and any public reading lists are posted on the LumiNUS portal for enrolled students.

If you are considering taking this course and would like a copy of the syllabus, please email kenneth.khoo@nus.edu.sg.
```

- [ ] **Step 3: Write `src/content/teaching/corporate-law-and-economics.md`**

```markdown
---
title: "Corporate Law and Economics"
code: "LL4400"
semesters: ["AY 2025/26 Sem 2"]
description: "Advanced seminar on the law-and-economics of corporate governance, takeovers, common ownership, shareholder activism, and disclosure regulation."
---

This seminar reviews canonical and recent empirical work in corporate law and economics. Students write a research paper.

For a copy of the current syllabus, email kenneth.khoo@nus.edu.sg.
```

- [ ] **Step 4: Write `src/content/teaching/advanced-corporate-finance.md`**

```markdown
---
title: "Advanced Corporate Finance Law"
code: "LL4500"
semesters: ["AY 2024/25 Sem 2"]
description: "Advanced course on the law and finance of corporate capital structure, securities issuance, M&A, and shareholder voting, with selected case studies and event studies."
---

Materials are posted on LumiNUS for enrolled students.
```

- [ ] **Step 5: Verify schema validation**

```bash
npx astro check
```

- [ ] **Step 6: Commit**

```bash
git add src/content/teaching/
git commit -m "Add 3 teaching entries (Company Law, Corporate L&E, Advanced Corp Finance)"
```

### Task 8: Create empty `news`, `talks`, `media` collections

**Files:**
- Create: `src/content/news/.gitkeep`, `src/content/talks/.gitkeep`, `src/content/media/.gitkeep`

- [ ] **Step 1: Create directories with .gitkeep files**

```bash
mkdir -p src/content/news src/content/talks src/content/media
touch src/content/news/.gitkeep src/content/talks/.gitkeep src/content/media/.gitkeep
```

- [ ] **Step 2: Verify build still passes (empty collections are valid)**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/content/news/.gitkeep src/content/talks/.gitkeep src/content/media/.gitkeep
git commit -m "Initialize empty news, talks, media collections"
```

---

## Phase 3 — Layout + components

### Task 9: Create `src/layouts/BaseLayout.astro`

**Files:**
- Create: `src/layouts/BaseLayout.astro`

- [ ] **Step 1: Write the layout**

```astro
---
import { ClientRouter } from 'astro:transitions';
import '../styles/global.css';
import Header from '../components/Header.astro';
import Footer from '../components/Footer.astro';

interface Props {
  title?: string;
  description?: string;
}

const { title, description } = Astro.props;
const pageTitle = title ? `${title} — Kenneth Khoo` : 'Kenneth Khoo';
const pageDescription = description ?? 'Assistant Professor at NUS Faculty of Law. Research in corporate governance, antitrust, and law and economics.';
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <meta name="description" content={pageDescription} />
    <title>{pageTitle}</title>
    <script is:inline>
      (function () {
        try {
          const stored = localStorage.getItem('theme');
          const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
          if (stored === 'dark' || (!stored && prefersDark)) {
            document.documentElement.classList.add('dark');
          }
        } catch (_) {}
      })();
    </script>
    <ClientRouter />
  </head>
  <body class="min-h-screen flex flex-col">
    <Header />
    <main class="flex-1 mx-auto w-full max-w-[960px] px-8 py-16">
      <slot />
    </main>
    <Footer />
  </body>
</html>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```
Expected: build passes. The placeholder `src/pages/index.astro` doesn't use BaseLayout yet, so no rendering changes.

- [ ] **Step 3: Commit**

```bash
git add src/layouts/BaseLayout.astro
git commit -m "Add BaseLayout with dark mode preflight + ClientRouter"
```

### Task 10: Create `src/components/Header.astro`

**Files:**
- Create: `src/components/Header.astro`

- [ ] **Step 1: Write the header**

```astro
---
import ModeToggle from './ModeToggle.astro';

const navItems = [
  { href: '/research/', label: 'Research' },
  { href: '/teaching/', label: 'Teaching' },
  { href: '/cv/', label: 'CV' },
  { href: '/news/', label: 'News' },
  { href: '/talks/', label: 'Talks' },
  { href: '/media/', label: 'Media' },
];
---

<header class="sticky top-0 z-50 border-b backdrop-blur" style="background: color-mix(in srgb, var(--color-bg) 80%, transparent); border-color: var(--color-border);">
  <div class="mx-auto max-w-[960px] px-8 h-16 flex items-center justify-between">
    <a href="/" class="font-semibold tracking-tight" style="color: var(--color-text);">Kenneth Khoo</a>
    <nav class="flex items-center gap-6">
      {navItems.map((item) => (
        <a href={item.href} class="text-sm" style="color: var(--color-text-muted);">{item.label}</a>
      ))}
      <ModeToggle />
    </nav>
  </div>
</header>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/components/Header.astro
git commit -m "Add Header component with sticky nav and ModeToggle slot"
```

### Task 11: Create `src/components/ModeToggle.astro`

**Files:**
- Create: `src/components/ModeToggle.astro`

- [ ] **Step 1: Write the component**

```astro
---
---
<button
  id="mode-toggle"
  type="button"
  aria-label="Toggle color mode"
  class="p-2 rounded hover:opacity-80"
  style="color: var(--color-text-muted);"
>
  <svg id="icon-sun" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="hidden dark:block">
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" />
  </svg>
  <svg id="icon-moon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="block dark:hidden">
    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
  </svg>
</button>

<script is:inline>
  document.getElementById('mode-toggle')?.addEventListener('click', () => {
    const isDark = document.documentElement.classList.toggle('dark');
    try { localStorage.setItem('theme', isDark ? 'dark' : 'light'); } catch (_) {}
  });
</script>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/components/ModeToggle.astro
git commit -m "Add ModeToggle with sun/moon SVG icons and localStorage persistence"
```

### Task 12: Create `src/components/Footer.astro`

**Files:**
- Create: `src/components/Footer.astro`

- [ ] **Step 1: Write the footer**

```astro
---
const year = new Date().getFullYear();
const links = [
  { href: 'mailto:kenneth.khoo@nus.edu.sg', label: 'Email' },
  { href: 'https://scholar.google.com/citations?user=DZ8K-s4AAAAJ', label: 'Google Scholar' },
  { href: 'https://github.com/kennethkhoocy', label: 'GitHub' },
  { href: 'https://www.linkedin.com/in/kenneth-khoo-72a49650', label: 'LinkedIn' },
  { href: 'https://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id=2570590', label: 'SSRN' },
];
---

<footer class="border-t mt-24 py-10" style="border-color: var(--color-border);">
  <div class="mx-auto max-w-[960px] px-8 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 text-sm" style="color: var(--color-text-muted);">
    <div class="flex flex-wrap gap-x-4 gap-y-1">
      {links.map((link) => (
        <a href={link.href} class="hover:underline" style="color: var(--color-text-muted);">{link.label}</a>
      ))}
    </div>
    <div>© {year} Kenneth Khoo · Built with Astro</div>
  </div>
</footer>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/components/Footer.astro
git commit -m "Add Footer with contact links and Astro credit"
```

### Task 13: Create `src/components/PaperRow.astro`

**Files:**
- Create: `src/components/PaperRow.astro`

- [ ] **Step 1: Write the component**

```astro
---
interface Props {
  title: string;
  year: number;
  coauthors: string[];
  venue: string;
  awards?: string[];
  ssrn_url?: string;
  pdf_url?: string;
}

const { title, year, coauthors, venue, awards = [], ssrn_url, pdf_url } = Astro.props;
const href = ssrn_url ?? pdf_url;
const coauthorLine = coauthors.length ? `with ${coauthors.join(', ')}` : null;
const metaParts = [coauthorLine, venue].filter(Boolean);
---

<div class="py-4 border-b" style="border-color: var(--color-border);">
  <div class="flex items-baseline justify-between gap-4">
    <div class="flex-1">
      {href ? (
        <a href={href} class="font-medium" style="color: var(--color-text);">{title}</a>
      ) : (
        <span class="font-medium" style="color: var(--color-text);">{title}</span>
      )}
      {awards.length > 0 && <span class="ml-2" style="color: var(--color-accent);" title={awards.join(' · ')}>★</span>}
      <div class="text-sm mt-1" style="color: var(--color-text-muted);">{metaParts.join(' · ')}</div>
    </div>
    <div class="font-mono text-sm shrink-0" style="color: var(--color-text-muted);">{year}</div>
  </div>
</div>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/components/PaperRow.astro
git commit -m "Add PaperRow component (title link → SSRN, meta line, award marker)"
```

### Task 14: Create `src/components/FeaturedPaper.astro`

**Files:**
- Create: `src/components/FeaturedPaper.astro`

- [ ] **Step 1: Write the component**

```astro
---
interface Props {
  title: string;
  year: number;
  coauthors: string[];
  venue: string;
  awards?: string[];
  summary?: string;
  ssrn_url?: string;
  pdf_url?: string;
}

const { title, year, coauthors, venue, awards = [], summary, ssrn_url, pdf_url } = Astro.props;
const href = ssrn_url ?? pdf_url;
const coauthorLine = coauthors.length ? `with ${coauthors.join(', ')}` : null;
const metaParts = [coauthorLine, venue, String(year)].filter(Boolean);
---

<article class="py-5">
  {href ? (
    <a href={href} class="text-lg font-medium block" style="color: var(--color-text);">{title}</a>
  ) : (
    <span class="text-lg font-medium block" style="color: var(--color-text);">{title}</span>
  )}
  <div class="text-sm mt-1" style="color: var(--color-text-muted);">
    {metaParts.join(' · ')}
    {awards.length > 0 && <span class="ml-2" style="color: var(--color-accent);" title={awards.join(' · ')}>★</span>}
  </div>
  {summary && <p class="mt-2" style="color: var(--color-text);">{summary}</p>}
</article>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/components/FeaturedPaper.astro
git commit -m "Add FeaturedPaper component (larger title, summary line, meta + award)"
```

### Task 15: Create `src/components/SectionDivider.astro`

**Files:**
- Create: `src/components/SectionDivider.astro`

- [ ] **Step 1: Write the component**

```astro
---
interface Props {
  label: string;
}
const { label } = Astro.props;
---

<div class="flex items-center gap-4 my-10">
  <span class="text-xs uppercase tracking-widest" style="color: var(--color-text-muted);">{label}</span>
  <div class="flex-1 border-t" style="border-color: var(--color-border);"></div>
</div>
```

- [ ] **Step 2: Verify build**

```bash
npm run build
```

- [ ] **Step 3: Commit**

```bash
git add src/components/SectionDivider.astro
git commit -m "Add SectionDivider component for inline section headings"
```

---

## Phase 4 — Assets

### Task 16: Copy CV PDF + headshot from legacy into `public/`

**Files:**
- Create: `public/cv/Kenneth Khoo CV.pdf`, `public/cv/Controlling_Shareholders.pdf`, `public/images/headshot.jpg`

- [ ] **Step 1: Create directories and copy files**

```bash
mkdir -p public/cv public/images
cp "_legacy-jekyll/cv/Kenneth Khoo CV.pdf" "public/cv/Kenneth Khoo CV.pdf"
cp "_legacy-jekyll/cv/Controlling_Shareholders.pdf" "public/cv/Controlling_Shareholders.pdf"
cp _legacy-jekyll/images/1760923711828.jpg public/images/headshot.jpg
```

If the `Controlling_Shareholders.pdf` source path doesn't exist, skip it; the URL is referenced from one publication entry but won't break the build if the asset is missing (only a 404 on direct download).

- [ ] **Step 2: Verify build**

```bash
npm run build
ls dist/cv/ dist/images/ 2>&1
```
Expected: PDFs and headshot copied into `dist/`.

- [ ] **Step 3: Commit**

```bash
git add public/
git commit -m "Copy CV PDF, Controlling Shareholders draft PDF, and headshot to public/"
```

---

## Phase 5 — Pages

### Task 17: Build `src/pages/index.astro` (Home)

**Files:**
- Modify (replace placeholder): `src/pages/index.astro`

- [ ] **Step 1: Write the home page**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import FeaturedPaper from '../components/FeaturedPaper.astro';
import SectionDivider from '../components/SectionDivider.astro';

const publications = await getCollection('publications', ({ data }) => data.featured);
// Featured papers ascend by sort_key so the older but more prestigious paper
// (Expanding Shareholder Voice) appears first, matching the previous site's order.
const featured = publications.sort((a, b) => (a.data.sort_key ?? 0) - (b.data.sort_key ?? 0));
---

<BaseLayout>
  <section class="grid grid-cols-1 md:grid-cols-[1fr_auto] gap-8 items-start">
    <div>
      <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">Kenneth Khoo</h1>
      <p class="mt-2 text-lg" style="color: var(--color-text-muted);">Assistant Professor, NUS Faculty of Law</p>
      <p class="mt-6 max-w-prose">Empirical research on corporate governance, antitrust, and the law-and-economics of financial markets. Previously a Program Fellow at Harvard Law School's Program on Corporate Governance.</p>
      <div class="mt-6 flex flex-wrap gap-4 text-sm">
        <a href="mailto:kenneth.khoo@nus.edu.sg">Email</a>
        <a href="https://scholar.google.com/citations?user=DZ8K-s4AAAAJ">Scholar</a>
        <a href="https://github.com/kennethkhoocy">GitHub</a>
        <a href="https://www.linkedin.com/in/kenneth-khoo-72a49650">LinkedIn</a>
        <a href="https://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id=2570590">SSRN</a>
      </div>
    </div>
    <img src="/images/headshot.jpg" alt="Kenneth Khoo" width="180" height="180" class="rounded-md" />
  </section>

  <SectionDivider label="Featured research" />

  {featured.map((p) => (
    <FeaturedPaper
      title={p.data.title}
      year={p.data.year}
      coauthors={p.data.coauthors}
      venue={p.data.venue}
      awards={p.data.awards}
      summary={p.data.summary}
      ssrn_url={p.data.ssrn_url}
      pdf_url={p.data.pdf_url}
    />
  ))}
</BaseLayout>
```

- [ ] **Step 2: Build and visually verify**

```bash
npm run dev
```
Open http://localhost:4321/ in a browser. Confirm: headshot loads, three featured papers appear, all paper titles link to SSRN.

- [ ] **Step 3: Commit**

```bash
git add src/pages/index.astro
git commit -m "Build home page with bio, contact links, headshot, 3 featured papers"
```

### Task 18: Build `src/pages/research.astro`

**Files:**
- Create: `src/pages/research.astro`

- [ ] **Step 1: Write the page**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import PaperRow from '../components/PaperRow.astro';
import SectionDivider from '../components/SectionDivider.astro';

const all = await getCollection('publications');
const sortDesc = (a: typeof all[0], b: typeof all[0]) => (b.data.sort_key ?? 0) - (a.data.sort_key ?? 0);
const published = all.filter((p) => p.data.status === 'published' || p.data.status === 'forthcoming').sort(sortDesc);
const working = all.filter((p) => p.data.status === 'working_paper' || p.data.status === 'under_review').sort(sortDesc);
---

<BaseLayout title="Research">
  <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">Research</h1>

  <SectionDivider label="Published" />
  {published.map((p) => (
    <PaperRow
      title={p.data.title}
      year={p.data.year}
      coauthors={p.data.coauthors}
      venue={p.data.venue}
      awards={p.data.awards}
      ssrn_url={p.data.ssrn_url}
      pdf_url={p.data.pdf_url}
    />
  ))}

  <SectionDivider label="Working" />
  {working.map((p) => (
    <PaperRow
      title={p.data.title}
      year={p.data.year}
      coauthors={p.data.coauthors}
      venue={p.data.venue}
      awards={p.data.awards}
      ssrn_url={p.data.ssrn_url}
      pdf_url={p.data.pdf_url}
    />
  ))}
</BaseLayout>
```

- [ ] **Step 2: Build and verify**

```bash
npm run build
```
Open `dist/research/index.html` in a browser. Confirm: two groups render, all 19 papers appear across them, titles link to SSRN.

- [ ] **Step 3: Commit**

```bash
git add src/pages/research.astro
git commit -m "Build /research/ page grouped by Published / Working"
```

### Task 19: Build `src/pages/cv.astro`

**Files:**
- Create: `src/pages/cv.astro`

- [ ] **Step 1: Write the page**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import SectionDivider from '../components/SectionDivider.astro';
import PaperRow from '../components/PaperRow.astro';

const all = await getCollection('publications');
const sortDesc = (a: typeof all[0], b: typeof all[0]) => (b.data.sort_key ?? 0) - (a.data.sort_key ?? 0);
const published = all.filter((p) => p.data.status === 'published' || p.data.status === 'forthcoming').sort(sortDesc);
const working = all.filter((p) => p.data.status === 'working_paper' || p.data.status === 'under_review').sort(sortDesc);
---

<BaseLayout title="CV">
  <div class="flex items-baseline justify-between gap-4">
    <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">Curriculum Vitae</h1>
    <a href="/cv/Kenneth Khoo CV.pdf" class="text-sm px-3 py-1.5 border rounded" style="border-color: var(--color-accent); color: var(--color-accent);">Download PDF ↓</a>
  </div>

  <p class="mt-3 text-lg" style="color: var(--color-text-muted);">Assistant Professor · NUS Faculty of Law</p>
  <p class="mt-1"><a href="mailto:kenneth.khoo@nus.edu.sg">kenneth.khoo@nus.edu.sg</a></p>

  <SectionDivider label="Appointments" />
  <ul class="space-y-2">
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2025–</span>Assistant Professor, NUS Faculty of Law</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2020–24</span>Lecturer, NUS Faculty of Law</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2015–20</span>Sheridan Fellow, NUS Faculty of Law</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2022–23</span>Program Fellow, Harvard Law School's Program on Corporate Governance (under Lucian Bebchuk)</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2019–21</span>Research Assistant for Professor Henry Hansmann, Yale Law School</li>
  </ul>

  <SectionDivider label="Education" />
  <ul class="space-y-2">
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2024</span>J.S.D., Yale Law School</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2019</span>LL.M., Yale Law School</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2018</span>M.Sc. Economics, London School of Economics</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2014</span>LL.B. (First Class Honours, top 5%), NUS</li>
    <li><span class="font-mono text-sm mr-3" style="color: var(--color-text-muted);">2014</span>B.Soc.Sci. (Honours, First Class) in Economics, NUS</li>
  </ul>

  <SectionDivider label="Awards" />
  <ul class="space-y-2 list-disc pl-5">
    <li>Best Academic Paper (Junior Category), 2024 Berkeley-ECGI Forum on Corporate Governance</li>
    <li>Best Paper Award for Junior Scholars, Asian Law and Economics Association 2025 Annual Conference</li>
    <li>Ministry of Trade and Industry (Economist Service) Best Thesis Prize, NUS</li>
    <li>Dean's List, NUS (2010, 2011, 2012, 2014)</li>
  </ul>

  <SectionDivider label="Research interests" />
  <p>Law and Economics, Law and Finance, Antitrust and Competition Law, Corporate Governance and Law, Financial Economics, Industrial Organization, Contract Theory.</p>

  <SectionDivider label="Publications" />
  <h3 class="text-sm uppercase tracking-widest mb-2" style="color: var(--color-text-muted);">Published</h3>
  {published.map((p) => (
    <PaperRow
      title={p.data.title}
      year={p.data.year}
      coauthors={p.data.coauthors}
      venue={p.data.venue}
      awards={p.data.awards}
      ssrn_url={p.data.ssrn_url}
      pdf_url={p.data.pdf_url}
    />
  ))}

  <h3 class="text-sm uppercase tracking-widest mt-8 mb-2" style="color: var(--color-text-muted);">Working</h3>
  {working.map((p) => (
    <PaperRow
      title={p.data.title}
      year={p.data.year}
      coauthors={p.data.coauthors}
      venue={p.data.venue}
      awards={p.data.awards}
      ssrn_url={p.data.ssrn_url}
      pdf_url={p.data.pdf_url}
    />
  ))}

  <SectionDivider label="Computing" />
  <p>R, Stata, Python, Mathematica, LaTeX (data analysis, visualization, simulation, typesetting).</p>

  <SectionDivider label="Professional activities" />
  <ul class="space-y-2 list-disc pl-5">
    <li>Co-Organizer/Host, Bocconi-Oxford Junior Scholars Workshop in Corporate Law (2020–2023)</li>
  </ul>
</BaseLayout>
```

- [ ] **Step 2: Build and verify the Download PDF button works**

```bash
npm run build
```
Open `dist/cv/index.html` in a browser. Click "Download PDF" — confirm it serves `/cv/Kenneth Khoo CV.pdf`.

- [ ] **Step 3: Commit**

```bash
git add src/pages/cv.astro
git commit -m "Build /cv/ page with appointments, education, awards, publications"
```

### Task 20: Build `src/pages/teaching/index.astro` and `src/pages/teaching/[slug].astro`

**Files:**
- Create: `src/pages/teaching/index.astro`, `src/pages/teaching/[slug].astro`

- [ ] **Step 1: Write `src/pages/teaching/index.astro`**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../../layouts/BaseLayout.astro';
import SectionDivider from '../../components/SectionDivider.astro';

const courses = await getCollection('teaching');
const sorted = courses.sort((a, b) => a.data.title.localeCompare(b.data.title));
---

<BaseLayout title="Teaching">
  <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">Teaching</h1>
  <SectionDivider label="Current and recent courses" />
  <ul class="space-y-6">
    {sorted.map((c) => (
      <li>
        <a href={`/teaching/${c.id}/`} class="text-lg font-medium block">{c.data.title}</a>
        {c.data.code && <div class="text-sm" style="color: var(--color-text-muted);">{c.data.code}</div>}
        <p class="mt-1">{c.data.description}</p>
      </li>
    ))}
  </ul>
</BaseLayout>
```

- [ ] **Step 2: Write `src/pages/teaching/[slug].astro`**

```astro
---
import { getCollection, render } from 'astro:content';
import BaseLayout from '../../layouts/BaseLayout.astro';

export async function getStaticPaths() {
  const courses = await getCollection('teaching');
  return courses.map((c) => ({ params: { slug: c.id }, props: { entry: c } }));
}

const { entry } = Astro.props;
const { Content } = await render(entry);
---

<BaseLayout title={entry.data.title}>
  <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">{entry.data.title}</h1>
  {entry.data.code && <div class="mt-1 text-sm" style="color: var(--color-text-muted);">{entry.data.code}</div>}
  {entry.data.semesters.length > 0 && (
    <div class="mt-1 text-sm" style="color: var(--color-text-muted);">Taught: {entry.data.semesters.join(' · ')}</div>
  )}
  <p class="mt-4 text-lg" style="color: var(--color-text);">{entry.data.description}</p>
  {entry.data.syllabus_url && (
    <p class="mt-4"><a href={entry.data.syllabus_url}>Syllabus (PDF)</a></p>
  )}
  <div class="mt-8">
    <Content />
  </div>
</BaseLayout>
```

- [ ] **Step 3: Build and verify**

```bash
npm run build
ls dist/teaching/
```
Expected: `dist/teaching/index.html`, plus one subdir per course slug each containing `index.html`.

- [ ] **Step 4: Commit**

```bash
git add src/pages/teaching/
git commit -m "Build /teaching/ index and /teaching/[slug]/ pages"
```

### Task 21: Build `news`, `talks`, `media` pages with empty-state rendering

**Files:**
- Create: `src/pages/news.astro`, `src/pages/talks.astro`, `src/pages/media.astro`

- [ ] **Step 1: Write `src/pages/news.astro`**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import SectionDivider from '../components/SectionDivider.astro';

const entries = await getCollection('news');
const sorted = entries.sort((a, b) => b.data.date.localeCompare(a.data.date));
const byYear: Record<string, typeof sorted> = {};
for (const e of sorted) {
  const yr = e.data.date.slice(0, 4);
  (byYear[yr] ??= []).push(e);
}
const years = Object.keys(byYear).sort((a, b) => b.localeCompare(a));
---

<BaseLayout title="News">
  <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">News</h1>
  {years.length === 0 ? (
    <p class="mt-6" style="color: var(--color-text-muted);">No updates posted yet.</p>
  ) : years.map((yr) => (
    <>
      <SectionDivider label={yr} />
      <ul class="space-y-3">
        {byYear[yr].map((e) => (
          <li class="flex gap-4">
            <span class="font-mono text-sm shrink-0" style="color: var(--color-text-muted);">{e.data.date}</span>
            <span>{e.data.body}</span>
          </li>
        ))}
      </ul>
    </>
  ))}
</BaseLayout>
```

- [ ] **Step 2: Write `src/pages/talks.astro`**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import SectionDivider from '../components/SectionDivider.astro';

const entries = await getCollection('talks');
const sorted = entries.sort((a, b) => b.data.date.localeCompare(a.data.date));
const byYear: Record<string, typeof sorted> = {};
for (const e of sorted) {
  const yr = e.data.date.slice(0, 4);
  (byYear[yr] ??= []).push(e);
}
const years = Object.keys(byYear).sort((a, b) => b.localeCompare(a));
---

<BaseLayout title="Talks">
  <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">Talks</h1>
  {years.length === 0 ? (
    <p class="mt-6" style="color: var(--color-text-muted);">No talks posted yet.</p>
  ) : years.map((yr) => (
    <>
      <SectionDivider label={yr} />
      <ul class="space-y-3">
        {byYear[yr].map((e) => (
          <li class="flex flex-col gap-1">
            <div class="flex gap-3">
              <span class="font-mono text-sm shrink-0" style="color: var(--color-text-muted);">{e.data.date}</span>
              <span>{e.data.venue}</span>
            </div>
            <div>
              {e.data.paper_ssrn_url ? (
                <a href={e.data.paper_ssrn_url}>{e.data.paper_title}</a>
              ) : (
                <span>{e.data.paper_title}</span>
              )}
              {e.data.slides_url && <a href={e.data.slides_url} class="ml-3 text-sm">[slides]</a>}
            </div>
          </li>
        ))}
      </ul>
    </>
  ))}
</BaseLayout>
```

- [ ] **Step 3: Write `src/pages/media.astro`**

```astro
---
import { getCollection } from 'astro:content';
import BaseLayout from '../layouts/BaseLayout.astro';
import SectionDivider from '../components/SectionDivider.astro';

const entries = await getCollection('media');
const sorted = entries.sort((a, b) => b.data.date.localeCompare(a.data.date));
const byYear: Record<string, typeof sorted> = {};
for (const e of sorted) {
  const yr = e.data.date.slice(0, 4);
  (byYear[yr] ??= []).push(e);
}
const years = Object.keys(byYear).sort((a, b) => b.localeCompare(a));
---

<BaseLayout title="Media">
  <h1 class="text-3xl font-semibold tracking-tight" style="color: var(--color-text);">Media</h1>
  {years.length === 0 ? (
    <p class="mt-6" style="color: var(--color-text-muted);">No media items posted yet.</p>
  ) : years.map((yr) => (
    <>
      <SectionDivider label={yr} />
      <ul class="space-y-3">
        {byYear[yr].map((e) => (
          <li>
            <div class="flex gap-3">
              <span class="font-mono text-sm shrink-0" style="color: var(--color-text-muted);">{e.data.date}</span>
              <span style="color: var(--color-text-muted);">{e.data.outlet}</span>
            </div>
            <a href={e.data.url}>{e.data.headline}</a>
            {e.data.note && <p class="text-sm mt-1" style="color: var(--color-text-muted);">{e.data.note}</p>}
          </li>
        ))}
      </ul>
    </>
  ))}
</BaseLayout>
```

- [ ] **Step 4: Build and verify**

```bash
npm run build
```
Expected: each page renders with "No items posted yet."

- [ ] **Step 5: Commit**

```bash
git add src/pages/news.astro src/pages/talks.astro src/pages/media.astro
git commit -m "Build /news/, /talks/, /media/ pages with empty-state messages"
```

### Task 22: Build redirect pages for old Jekyll URLs

**Files:**
- Create: `src/pages/about/index.astro`, `src/pages/publications/index.astro`, `public/about.html`

- [ ] **Step 1: Write `src/pages/about/index.astro`**

```astro
---
---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="refresh" content="0; url=/" />
    <link rel="canonical" href="https://kennethkhoocy.github.io/" />
    <title>Redirecting…</title>
  </head>
  <body>
    <p>Redirecting to <a href="/">/</a>…</p>
    <script>window.location.replace('/');</script>
  </body>
</html>
```

- [ ] **Step 2: Write `src/pages/publications/index.astro`**

```astro
---
---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="refresh" content="0; url=/research/" />
    <link rel="canonical" href="https://kennethkhoocy.github.io/research/" />
    <title>Redirecting…</title>
  </head>
  <body>
    <p>Redirecting to <a href="/research/">/research/</a>…</p>
    <script>window.location.replace('/research/');</script>
  </body>
</html>
```

- [ ] **Step 3: Write `public/about.html`**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="refresh" content="0; url=/" />
    <link rel="canonical" href="https://kennethkhoocy.github.io/" />
    <title>Redirecting…</title>
  </head>
  <body>
    <p>Redirecting to <a href="/">/</a>…</p>
    <script>window.location.replace('/');</script>
  </body>
</html>
```

- [ ] **Step 4: Build and verify**

```bash
npm run build
ls dist/about/index.html dist/about.html dist/publications/index.html
```
Expected: all three files exist.

- [ ] **Step 5: Commit**

```bash
git add src/pages/about src/pages/publications public/about.html
git commit -m "Add redirects for /about/, /about.html, /publications/ to preserve old URLs"
```

---

## Phase 6 — Deploy

### Task 23: Add GitHub Actions deploy workflow

**Files:**
- Create: `.github/workflows/deploy.yml`

NB: This deviates slightly from the spec's "deploy to gh-pages branch" wording. The modern flow uses `actions/deploy-pages@v4`, which deploys the Astro build artifact directly via GitHub Pages without a long-lived branch. The cutover (task 27) sets the Pages source to "GitHub Actions" instead of a branch. Same end state.

- [ ] **Step 1: Write the workflow**

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Build with Astro
        uses: withastro/action@v3

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/deploy.yml
git commit -m "Add GitHub Actions workflow: withastro/action@v3 → deploy-pages@v4"
```

### Task 24: Add post-build link checker script

**Files:**
- Create: `scripts/check_links.mjs`

- [ ] **Step 1: Write the script**

```js
import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';

const DIST = new URL('../dist/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

async function walk(dir, files = []) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) await walk(p, files);
    else if (entry.name.endsWith('.html')) files.push(p);
  }
  return files;
}

const htmlFiles = await walk(DIST);
const issues = [];
const linkRegex = /href="([^"#?]+)"/g;

for (const f of htmlFiles) {
  const text = await readFile(f, 'utf8');
  let m;
  while ((m = linkRegex.exec(text))) {
    const href = m[1];
    if (href.startsWith('http') || href.startsWith('mailto:') || href.startsWith('//')) continue;
    if (href === '/') continue;
    const target = href.startsWith('/') ? join(DIST, href) : join(f, '..', href);
    const normalized = target.endsWith('/') ? join(target, 'index.html') : target;
    try {
      await readFile(normalized);
    } catch {
      try {
        await readFile(join(target, 'index.html'));
      } catch {
        issues.push({ source: relative(DIST, f), href, expected: relative(DIST, normalized) });
      }
    }
  }
}

if (issues.length) {
  console.error(`Found ${issues.length} broken internal link(s):`);
  for (const i of issues) console.error(`  in ${i.source}: href="${i.href}" -> ${i.expected}`);
  process.exit(1);
} else {
  console.log(`All internal links resolved across ${htmlFiles.length} HTML files.`);
}
```

- [ ] **Step 2: Build, then run the checker**

```bash
npm run build
node scripts/check_links.mjs
```
Expected: "All internal links resolved..." with no broken links. If broken links appear, fix them in the offending page templates (commonly: wrong slugs, missing trailing slash given `trailingSlash: 'always'`).

- [ ] **Step 3: Commit**

```bash
git add scripts/check_links.mjs
git commit -m "Add post-build internal link checker"
```

### Task 25: Local end-to-end smoke test (dev server + manual click-through)

**Files:** none

- [ ] **Step 1: Start dev server**

```bash
npm run dev
```

- [ ] **Step 2: Open http://localhost:4321/ in a browser and visually verify each item below**

Checklist (mark each off):

- [ ] Header is sticky and has nav links: Research, Teaching, CV, News, Talks, Media + mode toggle
- [ ] Homepage shows headshot, bio, contact icons, 3 featured papers
- [ ] Each featured paper title links to the correct SSRN abstract page
- [ ] Mode toggle flips light/dark and persists across page reloads
- [ ] `/research/` shows two groups (Published, Working) with all 19 papers; sort is year desc within each group
- [ ] `/cv/` page shows the "Download PDF" button and clicking it downloads `Kenneth Khoo CV.pdf`
- [ ] `/teaching/` shows 3 courses; clicking a course goes to `/teaching/<slug>/`
- [ ] `/news/`, `/talks/`, `/media/` all show "No items posted yet."
- [ ] `/about/` redirects to `/`
- [ ] `/publications/` redirects to `/research/`
- [ ] `/about.html` redirects to `/`
- [ ] Resize browser to mobile width: header collapses cleanly, content remains readable, no horizontal scroll
- [ ] No console errors

- [ ] **Step 3: Stop dev server**

`Ctrl+C` the dev process.

- [ ] **Step 4: Final production build + link check before merging**

```bash
npm run build
node scripts/check_links.mjs
```

### Task 26: Push `astro-rewrite` to GitHub for review

**Files:** none

- [ ] **Step 1: Push branch**

```bash
git push -u origin astro-rewrite
```

- [ ] **Step 2: Open a PR for review (no merge yet)**

```bash
gh pr create --title "Astro rewrite: replace Jekyll with Astro 5 + Tailwind v4" --body "$(cat <<'EOF'
## Summary
- Replaces the Jekyll/Academic Pages site with an Astro 5 + TypeScript + Tailwind v4 build
- 19 publications migrated with SSRN URL coverage map
- Stripe-style minimal aesthetic, navy accent, dark mode with toggle
- Deploys via GitHub Actions (withastro/action@v3 + actions/deploy-pages@v4)
- Preserves old URLs: /about/, /about.html, /publications/

## Test plan
- [x] Local dev server smoke test (header, nav, mode toggle, featured papers, redirects)
- [x] Production build passes
- [x] Internal link checker passes
- [ ] Live smoke test after deploy + Pages source flip (task 28)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### Task 27: Cutover — merge to main + switch GitHub Pages source

**Files:** none (repo settings change)

- [ ] **Step 1: Confirm CI on the PR is green (the workflow will build but not deploy until Pages source is switched)**

```bash
gh pr checks
```

- [ ] **Step 2: Merge the PR (squash or merge as you prefer)**

```bash
gh pr merge --merge
```

- [ ] **Step 3: Verify the deploy workflow runs on main**

```bash
gh run watch
```
Wait for the workflow to complete successfully (or fail — if so, troubleshoot and re-deploy).

- [ ] **Step 4: Switch GitHub Pages source**

This is a manual step in the GitHub UI:

1. Open https://github.com/kennethkhoocy/kennethkhoocy.github.io/settings/pages
2. Under "Build and deployment", set **Source** to **GitHub Actions**
3. Save

- [ ] **Step 5: Trigger one deploy via the workflow_dispatch trigger to confirm the source change took effect**

```bash
gh workflow run "Deploy to GitHub Pages"
gh run watch
```

### Task 28: Live smoke test

**Files:** none

- [ ] **Step 1: Open https://kennethkhoocy.github.io/ in a browser**

Re-run the visual checklist from Task 25 Step 2, this time against the live URL. Verify:

- [ ] Site loads, headshot visible, fonts render
- [ ] All nav links work
- [ ] Mode toggle works and persists
- [ ] All 19 papers visible on /research/, titles link to SSRN
- [ ] /cv/ "Download PDF" works
- [ ] Redirect checks: open https://kennethkhoocy.github.io/about/ → should land at `/`; same for /about.html and /publications/
- [ ] Mobile rendering OK
- [ ] No 404s in the browser network tab

- [ ] **Step 2: If anything broken: open an issue capturing the symptom, fix on a new branch, PR, deploy, re-test.**

### Task 29: (Follow-up after 1 week) Delete `_legacy-jekyll/`

**Files:**
- Delete: `_legacy-jekyll/`

- [ ] **Step 1: Confirm the live site has been working for ~1 week with no regressions**

- [ ] **Step 2: Remove the legacy folder**

```bash
git rm -r _legacy-jekyll/
git commit -m "Remove _legacy-jekyll/ after 1-week safety window"
git push
```

- [ ] **Step 3: Verify the next deploy still passes**

```bash
gh run watch
```

---

## Self-review checklist (run before handing off)

- [ ] **Spec coverage**: every decision in §2 of the spec is implemented by some task (aesthetic via global.css; stack via tasks 2–3; pages via tasks 17–22; SSRN linking via task 6; dark mode via tasks 9 + 11; View Transitions via task 9; URL preservation via task 22).
- [ ] **Reference coverage**: all 19 publication entries appear in task 6; 3 teaching entries in task 7; talks/news/media handled as empty initially in task 8 + task 21.
- [ ] **Type consistency**: schema field names (`ssrn_url`, `pdf_url`, `coauthors`, `sort_key`, `featured`, `summary`, `awards`, `status`, `venue`, `year`, `title`) used identically across content.config.ts, all 19 YAML entries, PaperRow, FeaturedPaper, index/research/cv pages.
- [ ] **No placeholders**: every step has either runnable commands or complete code blocks.

If you find a missing task while implementing, add one inline rather than skipping.
