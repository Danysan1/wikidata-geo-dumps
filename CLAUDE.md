# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Pipeline that produces geographic dumps from Wikidata & web service that exposes them on. It filters the full Wikidata JSON dump for entities with coordinates (P625), makes sure that they are currently existing feature, then converts the result to GeoJSONSeq, FlatGeoBuf, and GeoParquet via jq and GDAL/OGR. The generated files are served as static downloads alongside a small landing page. Deployed to Wikimedia Toolforge as the tool `tool-wikidata-geo-dumps`.

## Architecture

The repo has three loosely coupled pieces glued together by the Toolforge buildpack:

- **Web service** — `dist/` is a static folder served by `serve` (`npm start`). The Toolforge web service exposes the generated dump files under `dist/dumps/<date>/`. `Procfile`'s `web:` entry runs `npm start`. `dist/dumps/index.html` is a Codex-styled static page that fetches `dist/dumps/index.json` and renders the per-dump file listing at `/dumps/`, taking the place of `serve`'s default directory listing for that path. Sub-paths (e.g. `/dumps/<date>/`) still fall through to the directory listing configured in `dist/serve.json`.

- **Dump generation pipeline** — `dump-generation/generate.sh` is invoked as a daily Toolforge job (see `toolforge/jobs.yaml`). It:
  1. Reads `/public/dumps/public/wikidatawiki/entities/latest-all.json.gz` (Toolforge's NFS-mounted Wikimedia dump path). This file weighs more than 150GB and contains more than 100 million items so it's critical that the filtering step is parallel, fast and optimized.
  2. Decompresses with `pigz`, `grep`s for `P625":` to drop non-place items, and fans out across cores via `parallel --pipe` to `jq -f dump-generation/filter.jq`. The filter (kept in its own file because `parallel` invokes commands through a shell that would interpret inline `|` characters as pipes) does the claim presence/absence check (P625 present; P585/P376/P580/P571/P1619/P582/P576/P3999 absent), strips the trailing `,` that each line of the Wikidata JSON-array dump carries, then emits one **GeoJSONSeq** Feature per item (`places.geojsonl`, RFC 8142 newline-delimited GeoJSON), swapping `[lat, lon]` → `[lon, lat]` for GeoJSON order. Filter rules are still being tightened — see the `#TODO` block at the top of `filter.jq`.
  3. Runs `ogr2ogr -f FlatGeobuf` against `places.geojsonl` to produce `places.fgb`, then converts FGB → GeoParquet via an inline Python heredoc using `geopandas` + `pyarrow` (declared in `requirements.txt`). GeoParquet is **not** produced by `ogr2ogr` because Toolforge's GDAL build lacks `libgdal-arrow-parquet`. `.geojson` (a single FeatureCollection) is only produced in `--test` mode because the file is too large in production.
  4. Output goes to `$TOOL_DATA_DIR/dist/dumps/<dump-date>/` (or `<dump-date>-test`), which is accessed also by the web service to allow users to download the generated geo dumps.
  5. Invokes `dump-generation/generate-index.py` to write `$TOOL_DATA_DIR/dist/dumps/index.json` — a listing of every non-`*-test` dump folder and the files inside (name + size). This file is consumed by `dist/dumps/index.html` to render the `/dumps/` index page.

## Build/runtime environment

Toolforge uses a Heroku-style buildpack. `project.toml` declares apt packages `gdal-bin` (provides `ogr2ogr`), `jq` (NDJSON → GeoJSONSeq conversion), `parallel` (fans the jq stage across cores), and `pigz` (parallel gzip decompression), as documented in https://wikitech.wikimedia.org/wiki/Help:Toolforge/Building_container_images#Installing_Apt_packages . `requirements.txt` adds the Python deps used in the FGB → GeoParquet step (`geopandas`, `pyarrow`). There is no node-side build step — `dist/` is committed as-is.

`Procfile` defines two process types: `web` (the static server) and `generate` (the dump pipeline). Toolforge's `jobs.yaml` references `command: generate` (and `generate --test`), which invokes the Procfile entry. The production job runs `@daily` with `cpu: 2`, `mem: 6Gi`, `timeout: 28800` (8 h), `retry: 1` — keep these in mind when changing the pipeline's resource profile.

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
- Load Codex CSS from CDN: `https://cdn.jsdelivr.net/npm/@wikimedia/codex/dist/codex.style.css`
  - Pin to a specific version in production (replace bare package name with `@wikimedia/codex@<version>`).
  - Documentation: https://doc.wikimedia.org/codex/main/
- **Codex CSS does not style plain HTML elements** — it only styles `.cdx-*` component classes.
  Apply design tokens to semantic HTML elements manually via CSS custom properties (see the `<style>` block in `index.html`).
- Use `.cdx-button`, `.cdx-button--fake-button`, `.cdx-button--weight-*`, `.cdx-button--action-*` etc. when a link should look like a button.
- Use Codex CSS custom properties (`--color-*`, `--spacing-*`, `--font-size-*`, `--border-*`, etc.) for all colours, spacing, and typography values. Always include a hardcoded fallback: `var(--color-base, #202122)`.
- Do not introduce custom colour values that diverge from the Codex palette; this ensures consistency with other Wikimedia tools and correct dark-mode behaviour when Codex adds it.

### WCAG 2.1 Level AA accessibility
- Include a **skip navigation link** (`<a class="wgd-skip-link" href="#main-content">`) as the first focusable element so keyboard users can jump past repeated navigation.
- Use semantic landmark elements: `<header>`, `<main id="main-content">`, `<footer>`, `<nav aria-label="…">`.
- Maintain a logical heading hierarchy (one `<h1>` per page, then `<h2>`, etc.).
- All links must have descriptive text — never use bare arrows ("→") or "click here" as the link label.
- All `<img>` and icon elements must have `alt` text or `aria-hidden="true"` if decorative.
- Colour contrast: use only Codex progressive/base/subtle colours, which are pre-validated for 4.5 : 1 contrast on white.
- Focus indicators must remain visible — do not use `outline: none` without an equivalent visible replacement.
- Use relative units (`rem`/`em`) for font sizes and spacing so that browser zoom works correctly.

## Important gotchas

- This repo is located in Wikimedia Foundation GitLab instance at `https://gitlab.wikimedia.org/toolforge-repos/wikidata-geo-dumps.git`. Pushing to git is not enough to deploy, it's necessary to build the project and update the server as described above.
- The pipeline is heavily idempotent: each step skips if its output file already exists. To force regeneration, delete the corresponding file under `$TOOL_DATA_DIR/dist/dumps/<date>/`.
- The jq filter operates on the raw Wikidata JSON dump format (`claims.P625[i].mainsnak.datavalue.value.{longitude,latitude}`), not on any simplified shape. The `select(...)` guards in `dump-generation/filter.jq` silently drop anything that doesn't match this exact shape — if Wikidata changes the dump format the output will go empty rather than fail loudly.
- Each line of the source dump is a JSON object with a trailing `,` (the dump is a JSON array printed one element per line); `filter.jq` strips it via `rtrimstr(",")` before `fromjson`. Anything that touches this stage must preserve that handling.
