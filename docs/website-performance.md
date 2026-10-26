# Website performance

The source site is in `website/`. Production deploys embed the shared `geist.css`
into each HTML page to remove the stylesheet request from the first render.
Edit the shared stylesheet; do not edit built HTML.

Build into a new directory:

```sh
python3 scripts/build-website.py /tmp/vox-site
```

Deploy the built site to the existing Cloudflare Pages production project:

```sh
sh scripts/deploy-website.sh --branch main
```

Run Lighthouse 13.5.0 with its default mobile simulation and desktop preset:

```sh
node scripts/audit-website.mjs
```

The audit checks all ten public pages sequentially in both modes. It saves HTML
and JSON reports under `output/lighthouse/`, prints category scores, and exits
unsuccessfully if any category scores below 100. Optional arguments override the
base URL and report directory. Timing scores can vary between runs; inspect the
reports before changing code.

The two variable fonts come from Vercel's `geist@1.8.2` package. Their license is
bundled in `website/fonts/LICENSE.txt`. After changing the full variable fonts,
regenerate the smaller Latin subsets with:

```sh
python3 -m pip install 'fonttools[woff]'
python3 scripts/optimize-website-fonts.py
```

Keep the subset character ranges synchronized with the font declarations in
`geist.css`. The full fonts cover characters outside those ranges. The analytics
gate runs after load and an animation frame, at idle, so it does not compete with
initial rendering; tracking still requires an affirmative gate response.

The deployment also generates Markdown documents and a small Pages Worker for
content negotiation, real 404s, and the public information API. See
[website agent readiness](website-agent-readiness.md) for the HTTP contract.
