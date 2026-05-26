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
