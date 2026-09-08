# Flockademic

Visualizes the documented spread of ALPR surveillance infrastructure over
time. See [Project.md](Project.md) for the full project brief (domain model,
data sources, temporal-provenance rules, MVP scope).

## Stack

Elixir/Phoenix/LiveView, PostgreSQL + PostGIS (via `geo_postgis`), Explorer
(dataframe/Parquet analytics — Project.md's "Flock" isn't a real published
library, so Explorer is the closest real equivalent), MapLibre GL JS, and
Tailwind CSS.

## Setup

1. `cp docker-compose.override.yml.example docker-compose.override.yml` — this
   publishes the Postgres port to `127.0.0.1` so the commands below can reach
   the containerised DB. The base `docker-compose.yml` deliberately does not
   publish it (see [docs/security-hardening.md](docs/security-hardening.md),
   SEC-1); the override is git-ignored and must never reach a deployment host.
2. Start the dev database: `docker compose up -d db` (Postgres 17 + PostGIS 3.5)
3. `mix setup` — fetches deps, creates/migrates the DB, installs the
   Tailwind/esbuild binaries
4. `npm install --prefix assets` — installs `maplibre-gl` (not wired into
   `mix setup`: `mix cmd` can't invoke npm's `.cmd` shim on Windows)
5. `mix phx.server` (or `iex -S mix phx.server`)

Then visit [`localhost:4001`](http://localhost:4001) (pinned off the Phoenix default 4000 to avoid clashing with other local projects).

### Basemap tiles

The map uses CARTO's basemap tiles, which need a free API key — without one
the tiles render with an "API KEY REQUIRED" watermark. Get a key at
<https://carto.com/basemaps/apikey/> and set `CARTO_API_KEY` in `.env`
(loaded by both `docker compose` and `mix phx.server` — see
`config/runtime.exs`). It's sent to the browser with every tile request, so
it's a plain config value, not a server secret.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Ingesting camera data

Two source adapters exist (`Flockademic.Ingest.Source` behaviour):

* **`Flockademic.Ingest.OSM`** — live queries against the public Overpass
  API for a bounding box. Fine for small areas/spot-checks, but the shared
  public instance rate-limits hard well below the size of a US state.
  `Flockademic.Ingest.run_grid/3` tiles a larger bbox into smaller
  requests to work around this, but it's still not the right tool for
  comprehensive coverage.

* **`Flockademic.Ingest.OSMExtract`** — the production path. Reads a
  GeoJSON file you've pre-filtered from a bulk regional OSM extract with
  [osmium](https://osmcode.org/osmium-tool/), so it never touches the
  shared Overpass API at all. This is how the current dataset (~135,700
  cameras nationwide) was built:

  ```bash
  # download a state extract, e.g. from https://download.geofabrik.de/north-america/us/
  curl -LO https://download.geofabrik.de/north-america/us/georgia-latest.osm.pbf

  # filter to ALPR nodes only, then export to GeoJSON with real OSM ids
  # plus each node's own edit version/timestamp
  # (osmium-tool via Docker avoids installing it natively)
  docker run --rm -v "$PWD:/data" stefda/osmium-tool \
    osmium tags-filter -o /data/alpr.osm.pbf /data/georgia-latest.osm.pbf n/surveillance:type=ALPR

  echo '{"attributes": {"id": true, "version": true, "timestamp": true}}' > export-config.json
  docker run --rm -v "$PWD:/data" stefda/osmium-tool \
    osmium export -c /data/export-config.json -o /data/alpr.geojson /data/alpr.osm.pbf
  ```

  Then, from an `iex -S mix` session (or a script run with `mix run`):

  ```elixir
  Flockademic.Ingest.run(Flockademic.Ingest.OSMExtract, path: "alpr.geojson")
  ```

  Each feature's own `@timestamp` becomes its `observed_at` — for the
  roughly half of nodes still at `@version` 1, that's the node's real OSM
  creation date, not one shared batch date. (`opts[:observed_at]` is still
  accepted as a fallback for features without a `@timestamp`, e.g. a file
  exported without the `export-config.json` above — pass the extract's own
  `osm_base` timestamp then, checkable with `osmium fileinfo`.) `@version`
  is stashed in `metadata["osm_version"]` so a camera detail view can flag
  that anything above 1 has been edited since creation, meaning
  `first_observed_at` may postdate the camera's *actual* first OSM
  appearance — the true creation date requires the full edit history
  (Geofabrik's `*-internal.osh.pbf`, gated behind an OSM account login
  since it carries changeset/user data), not this current-state extract.

  Both adapters funnel through the same `Flockademic.Ingest.OSMTags`
  normalization and `Flockademic.Cameras.ingest_observation/1`'s
  idempotent upsert, so running either one repeatedly (or both, over
  overlapping areas) never creates duplicates.

### Nationwide ingestion — don't forget the territories

Geofabrik's combined `north-america/us-latest.osm.pbf` only bundles the 50
states + DC. **Puerto Rico and the US Virgin Islands are separate
extracts** (`north-america/us/puerto-rico-latest.osm.pbf` and
`.../us-virgin-islands-latest.osm.pbf`) and are silently excluded from the
"nationwide" file — this bit us once already (172+ real documented
cameras missing with no error or warning). If you re-run a full
nationwide ingest, fetch and filter those two files the same way and feed
the merged GeoJSON (`osmium merge a.osm.pbf b.osm.pbf -o merged.osm.pbf`
before exporting, or just run the ingest twice) through
`Flockademic.Ingest.OSMExtract` as well.

The scheduled re-ingestion below sidesteps this by deriving its region
list from `Flockademic.Regions` (which covers the 50 states + DC) plus
two hardcoded entries for the territories — see
`Flockademic.Ingest.Scheduler`'s moduledoc.

## Scheduled re-ingestion

`Flockademic.Ingest.Scheduler` is a GenServer that periodically re-runs
the live Overpass adapter (`Flockademic.Ingest.OSM`) against one US
state/territory per tick — cycling through all of them over time — then
recomputes region snapshots and broadcasts `{:snapshot_complete, stats}`
on the `"camera_updates"` PubSub topic. This is Project.md's "Phase 5 —
Production ingestion": it's what lets `first_observed_at` keep
accumulating real, camera-specific history going forward instead of
staying frozen at whatever the last manual bulk-extract run captured.

**Off by default** in every environment, since it hits the shared public
Overpass API on a timer once enabled — that's a deliberate choice, not
something dev/test should ever do unannounced. To turn it on:

* Locally: `config :flockademic, Flockademic.Ingest.Scheduler, enabled: true`
* In production: set `SCHEDULED_INGEST_ENABLED=true` (and optionally
  `SCHEDULED_INGEST_INTERVAL_MS`, default one day) — see
  `config/runtime.exs`.

Region bounding boxes are approximate (good enough for a periodic top-up
sweep, not the authoritative source — that's still the bulk
Geofabrik/osmium path above), so a camera right on a state line might be
picked up by a neighboring region's box instead, or vice versa;
idempotent ingestion means that never creates a duplicate either way.

Region boundaries (for the state/county selector and stats) come from the
Census Bureau's TIGERweb service: `Flockademic.Regions.TigerWeb.
import_state("GA")`.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for
the full text.

