# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. Remember to update this file when changing the architecture or behavior of the project, without delving into in-depth details that can easily be deduced from the file you are working on.

## What this project is

Pipeline that produces geographic dumps from Wikidata & web service that exposes them on. It filters the full Wikidata JSON dump for entities with coordinates (P625), makes sure that they are currently existing feature, then converts the result to GeoJSONSeq, FlatGeoBuf, and GeoParquet via jq and GDAL/OGR. The generated files are served as static downloads alongside a small landing page. Deployed to Wikimedia Toolforge as the tool `tool-wikidata-geo-dumps`.

## Architecture

The repo has three loosely coupled pieces glued together by the Toolforge buildpack:

- **Web service** — `dist/` is a static folder served by `serve` (`npm start`). Dump files are exposed under `dist/dumps/<date>/`. `dist/index.html` loads `dist/dumps-listing.js`, which fetches `dumps/index.json` at runtime and renders the file listing. Sub-paths fall through to the directory listing configured in `dist/serve.json`.

- **Dump generation pipeline** — `dump-generation/generate.sh` runs as a daily Toolforge job. It decompresses the NFS-mounted Wikidata dump (150 GB+, 100 M+ items), pre-filters with `grep -F` for speed, then fans out to `jq -f dump-generation/filter.jq` in parallel. The filter keeps only items with P625 coordinates and no claims indicating the feature is historical/ended, and emits one GeoJSONSeq feature per item (`places.geojsonl`) with `id`, `name`/`name:en`, and `commons` properties. Filter rules are still being tightened — see the `#TODO` block at the top of `filter.jq`. `ogr2ogr` converts the result to FlatGeoBuf; a Python step produces GeoParquet via `geopandas`/`pyarrow`. Output lands in `$TOOL_DATA_DIR/dist/dumps/<date>/`. Finally, `dump-generation/generate-index.py` writes `$TOOL_DATA_DIR/dist/dumps/index.json` for the web UI.

## Build/runtime environment

Toolforge uses a Heroku-style buildpack. `project.toml` declares apt packages (`gdal-bin`, `jq`, `parallel`, `pigz`); `requirements.txt` adds Python deps (`geopandas`, `pyarrow`). No node-side build step — `dist/` is committed as-is.

`Procfile` defines two process types: `web` (static server) and `generate` (dump pipeline). `toolforge/jobs.yaml` schedules `generate` daily with `cpu: 2`, `mem: 2Gi`, `timeout: 28800`.

## Common commands

```sh
# Local: serve the dist folder for development
npm run dev

# Toolforge web entry: copies dist/ into $TOOL_DATA_DIR/dist/ then serves it.
# Requires $TOOL_DATA_DIR — do not run locally without it.
npm start

# Run the pipeline in test mode (uses only a subset of the source dump)
./dump-generation/generate.sh --test

# Toolforge: rebuild image and restart the web service after pushing to GitLab
./toolforge/build-and-update-web-service.sh

# Toolforge: force the daily generation job to re-run
./toolforge/force-dump-generation.sh

# Toolforge: (re)load job definitions from jobs.yaml
toolforge jobs load toolforge/jobs.yaml
```

## Web interface — design system & accessibility

All changes to the web pages must follow:

### Wikimedia Codex design system
- Load Codex CSS from CDN, pinned to a specific version.
- **Codex CSS does not style plain HTML elements** — only `.cdx-*` classes. Apply design tokens to semantic elements manually via CSS custom properties with hardcoded fallbacks (e.g. `var(--color-base, #202122)`).
- Use Codex CSS custom properties (`--color-*`, `--spacing-*`, `--font-size-*`, etc.) for all colours, spacing, and typography. Do not introduce custom colour values.

### WCAG 2.1 Level AA accessibility
- First focusable element must be a skip navigation link to `#main-content`.
- Use semantic landmarks: `<header>`, `<main id="main-content">`, `<footer>`, `<nav aria-label="…">`.
- One `<h1>` per page; logical heading hierarchy below it.
- All links must have descriptive text; all images must have `alt` or `aria-hidden="true"`.
- Do not use `outline: none` without a visible focus replacement.
- Use `rem`/`em` for font sizes and spacing.

## Important gotchas

- Pushing to GitLab is not enough to deploy — you must also rebuild the image and restart the web service (see commands above).
- The pipeline is idempotent: each step skips if its output already exists. To force regeneration, delete the relevant file under `$TOOL_DATA_DIR/dist/dumps/<date>/`.
- `filter.jq` operates on raw Wikidata dump JSON and silently drops items that don't match the expected shape — if Wikidata changes the dump format, output will go empty rather than fail loudly.
