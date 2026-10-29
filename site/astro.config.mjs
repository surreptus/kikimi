import { defineConfig } from 'astro/config';

// Served from GitHub Pages at https://surreptus.github.io/aomame/. The privacy policy and terms are the app's own
// files (../Aomame/Privacy.md, Terms.md), so the site can't drift from what the app shows.
export default defineConfig({
  site: 'https://surreptus.github.io',
  base: '/aomame',
  vite: { server: { fs: { allow: ['..'] } } },
});
