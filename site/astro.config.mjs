import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Served from GitHub Pages at https://surreptus.github.io/kikimi/. The privacy policy and terms are the app's own
// files (../Kikimi/Privacy.md, Terms.md), so the site can't drift from what the app shows. The guide is Starlight, under /guide/.
export default defineConfig({
  site: 'https://surreptus.github.io',
  base: '/kikimi',
  integrations: [
    starlight({
      title: 'Kikimi',
      description: 'Learn a language from videos you already own. Private, on your Mac.',
      favicon: '/favicon.svg',
      customCss: ['./src/styles/starlight.css'],
      components: { SiteTitle: './src/components/SiteTitle.astro' },
      social: [{ icon: 'github', label: 'Source on GitHub', href: 'https://github.com/surreptus/kikimi' }],
      lastUpdated: false,
      sidebar: [
        { label: 'Kikimi', items: [
          { label: 'Home', link: '/' }, { slug: 'download' }, { slug: 'faq' }, { slug: 'changelog' },
        ] },
        { label: 'Start here', items: [{ slug: 'guide/getting-started' }, { slug: 'guide/importing-videos' }] },
        { label: 'Using Kikimi', items: [{ slug: 'guide/player' }, { slug: 'guide/words' }, { slug: 'guide/lessons-and-reviews' }, { slug: 'guide/shadowing' }] },
        { label: 'Looking after it', items: [{ slug: 'guide/backups' }, { slug: 'guide/troubleshooting' }] },
        { label: 'About', items: [
          { label: 'Privacy policy', link: '/privacy/' }, { label: 'Terms of use', link: '/terms/' }, { label: 'Acknowledgements', link: '/acknowledgements/' },
        ] },
      ],
    }),
  ],
  vite: { server: { fs: { allow: ['..'] } } },
});
