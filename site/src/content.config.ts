import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

// heroNote: a line of small print under the hero's buttons (see src/components/Hero.astro).
export const collections = { docs: defineCollection({ loader: docsLoader(), schema: docsSchema({ extend: z.object({ heroNote: z.string().optional() }) }) }) };
