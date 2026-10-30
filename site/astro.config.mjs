import { defineConfig } from 'astro/config';

// Served from GitHub Pages at https://surreptus.github.io/kikimi/. The privacy policy and terms are the app's own
// files (../Kikimi/Privacy.md, Terms.md), so the site can't drift from what the app shows.
export default defineConfig({
  site: 'https://surreptus.github.io',
  base: '/kikimi',
  vite: { server: { fs: { allow: ['..'] } } },
});
