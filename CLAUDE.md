# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Pipeline that produces geographic dumps from Wikidata & web service that exposes them on. It filters the full Wikidata JSON dump for entities with coordinates (P625), makes sure that they are currently existing feature, then converts the filtered NDJSON to GeoJSON, FlatGeoBuf, and GeoParquet via GDAL/OGR. The generated files are served as static downloads alongside a small landing page. Deployed to Wikimedia Toolforge as the tool `tool-wikidata-geo-dumps`.

## Architecture

The repo has three loosely coupled pieces glued together by the Toolforge buildpack:

- **Web service** — `dist/` is a static folder served by `serve` (`npm start`). The Toolforge web service exposes the generated dump files under `dist/dumps/<date>/`. `Procfile`'s `web:` entry runs `npm start`.

- **Dump generation pipeline** — `dump-generation/generate.sh` is invoked as a daily Toolforge job (see `toolforge/jobs.yaml`). It:
  1. Reads `/public/dumps/public/wikidatawiki/entities/latest-all.json.gz` (Toolforge's NFS-mounted Wikimedia dump path).
  2. Greps `P625":` and pipes through `wikibase-dump-filter` (npm dep) with `--simplify --omit aliases --claim 'P625&~P585&~P376&~P580&~P571&~P1619&~P582&~P576&~P3999'` to produce `places.ndjson`. The claim filter requires P625 (coordinates) present and excludes items with P585/P376/start/end-date qualifiers — these rules are still being tightened (see `#TODO` lines in `generate.sh`).
  3. Pre-converts the wikibase-shaped NDJSON to **GeoJSONSeq** (`places.geojsonl`, RFC 8142 newline-delimited GeoJSON Features) with a small `jq` filter that walks `claims.P625` and emits one Feature per coordinate pair. This is the format every downstream step reads.
  4. Runs `ogr2ogr` against `places.geojsonl` to produce `.fgb` (FlatGeobuf) and `.parquet` (GeoParquet); `.geojson` (a single FeatureCollection) is only produced in `--test` mode because the file is too large in production.
  5. Output goes to `$TOOL_DATA_DIR/dist/dumps/<dump-date>/` (or `<dump-date>-test`), which is accessed also by the web service to allow users to download the generated geo dumps.

- **Dormant custom GDAL driver** — `dump-generation/gdal_Wikidata.py` is a Python plugin driver (`DRIVER_NAME = "Wikidata"`) that taught OGR to read wikibase-dump-filter NDJSON directly, emitting `POINT` features with id/modified/label_en/description_en (plus optional second-language label/description via `LANG=` open option). It is **no longer wired into the pipeline** — Toolforge's buildpack environment couldn't reliably bootstrap GDAL's embedded Python interpreter (`ModuleNotFoundError: No module named 'encodings'`), so we replaced this path with the jq pre-conversion above. The file is kept on disk as a reference; re-enabling it would require re-adding `python3-full` / `libpython3-all-dev` to `project.toml` AND restoring the `GDAL_PYTHON_DRIVER_PATH` / `GDAL_DRIVER_PATH` / `PYTHONSO` / `PYTHONHOME` exports in `generate.sh`.

## Build/runtime environment

Toolforge uses a Heroku-style buildpack. `project.toml` declares apt packages `gdal-bin` (provides `ogr2ogr`) and `jq` (the active NDJSON → GeoJSONSeq conversion), as documented in https://wikitech.wikimedia.org/wiki/Help:Toolforge/Building_container_images#Installing_Apt_packages .
There is no node-side build step — `dist/` is committed as-is.

`Procfile` defines two process types: `web` (the static server) and `generate` (the dump pipeline). Toolforge's `jobs.yaml` references `command: generate` (and `generate --test`), which invokes the Procfile entry.

## Common commands

```sh
# Local: serve the dist folder
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

## Important gotchas

- This repo is located in Wikimedia Foundation GitLab instance at `https://gitlab.wikimedia.org/toolforge-repos/wikidata-geo-dumps.git`. Pushing to git is not enough to deploy, it's necessary to build the project and update the server as described above.
- Production filtering inside `generate.sh` is currently guarded by `exit 1` (line ~61) until the filter rules are finalized. Only `--test` mode actually runs end-to-end today.
- The pipeline is heavily idempotent: each step skips if its output file already exists. To force regeneration, delete the corresponding file under `$TOOL_DATA_DIR/dist/dumps/<date>/`.
- The jq filter assumes wikibase-dump-filter `--simplify` shape: `claims.P625` is an array of `[lat, lon]` numeric pairs. GeoJSON expects `[lon, lat]`, so the filter swaps them. Changing `--simplify` or pulling a non-simplified P625 will silently produce empty output (the `select(...)` guards drop everything).
- `dump-generation/places.json` and `dump-generation/x.geojson` in the working tree are local scratch files — they are not consumed by the pipeline.
