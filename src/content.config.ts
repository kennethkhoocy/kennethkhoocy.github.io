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
    materials_url: z.string().url().optional(),
    materials_repo: z.string().default('kennethkhoocy/teaching'),
    materials_branch: z.string().default('main'),
    materials_path: z.string().optional(),
    description: z.string(),
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

const software = defineCollection({
  loader: glob({ pattern: '**/*.yml', base: './src/content/software' }),
  schema: z.object({
    name: z.string(),
    repo_url: z.string().url(),
    language: z.string().optional(),
    description: z.string(),
    sort_key: z.number().int().optional(),
  }),
});

export const collections = { publications, teaching, media, software };
