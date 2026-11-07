// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Deployed to GitHub Pages: https://carloshmartins.github.io/proof
export default defineConfig({
	site: 'https://carloshmartins.github.io',
	base: '/proof',
	integrations: [
		starlight({
			title: 'proof',
			description: 'Evidence that an iOS change actually works, for coding agents and the people reviewing their work.',
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/carloshmartins/proof' }],
			editLink: { baseUrl: 'https://github.com/carloshmartins/proof/edit/main/docs/' },
			lastUpdated: false,
			sidebar: [
				{
					label: 'Start here',
					items: [
						{ label: 'What proof does', slug: 'start/what-it-does' },
						{ label: 'Install', slug: 'start/install' },
						{ label: 'Set up your app', slug: 'start/setup' },
						{ label: 'Use it with a coding agent', slug: 'start/agents' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Build and test', slug: 'guides/build-and-test' },
						{ label: 'Drive the simulator', slug: 'guides/simulator' },
						{ label: 'Before and after', slug: 'guides/snaps' },
						{ label: 'Branches: trunk and base', slug: 'guides/branches' },
						{ label: 'Stacked pull requests', slug: 'guides/stacks' },
						{ label: 'Flows', slug: 'guides/flows' },
						{ label: 'The report', slug: 'guides/report' },
						{ label: 'Accessibility identifiers', slug: 'guides/accessibility' },
						{ label: 'PR review comments', slug: 'guides/pr-comments' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Conventions', slug: 'reference/conventions' },
						{ label: 'JSON output', slug: 'reference/json-output' },
						{ label: 'Commands', items: [{ autogenerate: { directory: 'reference/commands' } }] },
						{ label: 'How it works', slug: 'reference/how-it-works' },
						{ label: 'Troubleshooting', slug: 'reference/troubleshooting' },
					],
				},
			],
		}),
	],
});
