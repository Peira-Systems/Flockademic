# Security hardening — pre-deployment

Tracking doc for the security review done ahead of the first internet-facing
deployment (app in a Docker container, Caddy reverse proxy, Postgres in a
sibling container). Source review covered the Docker/compose setup, Phoenix
config, router, controllers, LiveViews, the data-access layer, ingest paths,
JS hooks, and dependency versions.

Severity: **HIGH** = fix before any internet exposure · **MEDIUM** = fix before
or immediately after launch · **LOW** = fix soon · **INFO** = hygiene / do when
convenient.

## Status

All code items done on branch `security-hardening` (this doc + one follow-up
commit). Remaining work is operational, not code:

| Item | Status |
|------|--------|
| SEC-1 Postgres port / password | ✅ done — port unpublished, `POSTGRES_PASSWORD` hard-required |
| SEC-2 `/analytics` pool exhaustion | ✅ done — `Regions.RankingsCache` (ETS, invalidated on ingest) |
| SEC-3 CSP header | ✅ done — `FlockademicWeb.Plugs.ContentSecurityPolicy` (nonce-based), prod/test only |
| SEC-4 `force_ssl` Host bypass | ✅ done — `exclude: []` (overrides Plug.SSL's default `localhost` carve-out) |
| SEC-5 TigerWeb query interpolation | ✅ done — `stusab`/FIPS format-validated |
| SEC-6 `/api` rate limiting | ✅ done — Caddy `rate_limit` (custom image, `docker/caddy/Dockerfile`) |
| SEC-7 CARTO key referrer lock | ⏳ **operator action** — restrict the key in the CARTO dashboard |
| SEC-8 `example.env` placeholders | ✅ done — placeholders emptied, generation commands documented |
| SEC-9 audit tooling | ✅ done — `mix_audit` + `sobelow` in deps, `precommit`, and CI (`.github/workflows/ci.yml`) |
| SEC-10 auto-migrations note | ✅ documented — acceptable for single-container deploys |

**Verified against a local prod-mode `docker compose` stack:**

- SEC-1 — `db` port not published (`5432/tcp` only), unreachable from the host;
  compose refuses to start without `POSTGRES_PASSWORD` / `SECRET_KEY_BASE`.
- SEC-3 — `Content-Security-Policy` (+ per-request nonce) present on HTML
  responses through Caddy; CARTO tiles / maplibre worker / LiveView socket
  work with no CSP violations.
- SEC-4 — `Host: localhost` over plain HTTP now 301s to https (was 200);
  https responses carry `strict-transport-security: max-age=31536000`.
- SEC-6 — custom Caddy image has `http.handlers.rate_limit`, Caddyfile
  validates, and a 330-request burst produced 30× `429`.

**Still to check against the real host:** `nmap` for 5432 from outside; a
concurrent load test on `/analytics` (SEC-2); the map end-to-end in a real
browser over the production cert (SEC-3).

---

## Must fix before deployment

### SEC-1 — PostgreSQL published to all host interfaces · HIGH

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`docker-compose.yml`](../docker-compose.yml) `db.ports`, plus
  `db.environment.POSTGRES_PASSWORD` and [`example.env`](../example.env)
- **Problem:** `ports: - "${POSTGRES_PORT:-5432}:5432"` binds Postgres to
  `0.0.0.0:5432`, so on an internet-facing host the database is directly
  reachable from the internet. The app container reaches Postgres over the
  private compose network (`db:5432`) and does not need the port published.
  Compounding factors:
  - `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}` silently falls back to
    `postgres` when the env var is unset/empty (unlike `SECRET_KEY_BASE`, which
    is hard-required with `:?`).
  - `example.env` ships `POSTGRES_PASSWORD=change-me`.
- **Fix:**
  1. Remove the `ports:` block from the `db` service entirely. If host access
     is genuinely needed for backups, bind to loopback only:
     `"127.0.0.1:5432:5432"`.
  2. Make `POSTGRES_PASSWORD` hard-required:
     `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required — see example.env}`
     (also update the `DATABASE_URL` interpolation and the healthcheck's
     `-U` accordingly if needed).
  3. Update `example.env` to say "generate a strong value, do not deploy the
     placeholder" rather than `change-me`.
  4. Do backups via `docker compose exec db pg_dump ...` or a backup sidecar,
     not a published port.
  5. Local dev still needs the port (host `mix test` / `mix phx.server` talk
     to the containerised DB), so that lives in a git-ignored
     `docker-compose.override.yml` (from `.example`), loopback-only, which
     compose merges automatically and which must never reach a deploy host.
- **Acceptance:** `nmap`/`ss` from outside the host shows 5432 closed;
  `docker compose config` shows no `db` port mapping (or loopback only);
  bringing the stack up with `POSTGRES_PASSWORD` unset fails fast with a clear
  message.
- **Verified** against the local prod stack (override removed): `db` container
  shows `5432/tcp` only (not `0.0.0.0:5432->5432`), `Test-NetConnection
  localhost:5432` → False, and `docker compose config` errors out with
  `POSTGRES_PASSWORD` / `SECRET_KEY_BASE` unset.

### SEC-2 — `/analytics` DB connection-pool exhaustion · MEDIUM

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`lib/flockademic_web/live/analytics_live.ex`](../lib/flockademic_web/live/analytics_live.ex)
  `mount/3` → [`lib/flockademic/regions.ex`](../lib/flockademic/regions.ex)
  `region_rankings/1` (and, lower risk, `compute_daily_snapshots/1`)
- **Problem:** Every unauthenticated `/analytics` load runs a ~3.6s nationwide
  spatial join (nested-loop, one index scan per ~3,100 counties) with
  `timeout: 60_000`, holding a DB connection the whole time. `POOL_SIZE`
  defaults to 10. ~10 concurrent visitors (or a trivial loop) starve the pool
  and stall DB access site-wide for seconds-to-a-minute.
- **Fix (pick one, prefer the first):**
  1. Cache the `region_rankings/1` result in ETS, invalidated on ingest — same
     pattern as `Flockademic.Cameras.GeoJSONCache`. Rankings only change after
     an ingest run.
  2. Precompute rankings during ingest / `compute_daily_snapshots/1` and read
     the stored rows on page load.
  3. At minimum: drop the per-query `timeout` back toward the Ecto default so a
     stuck query can't hog a connection for a full minute, and consider a
     dedicated small pool or `Task.async` concurrency cap for this query.
- **Acceptance:** hitting `/analytics` 50× concurrently (e.g. `hey`/`wrk`)
  leaves the map page and `/api/cameras.geojson` responsive throughout; the
  expensive query runs at most once per ingest.

---

## Worth addressing

### SEC-3 — No Content-Security-Policy header · LOW/MEDIUM

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`lib/flockademic_web/router.ex`](../lib/flockademic_web/router.ex)
  `:browser` pipeline; inline `<script>` in
  [`lib/flockademic_web/components/layouts/root.html.heex`](../lib/flockademic_web/components/layouts/root.html.heex)
- **Problem:** `put_secure_browser_headers` sets X-Frame-Options /
  X-Content-Type-Options / Referrer-Policy etc., but there is no CSP. The app
  renders DB-sourced strings (manufacturer, operator, `source_record_id`) into
  the camera panel — HEEx auto-escaping currently prevents stored XSS, but CSP
  is worthwhile defense-in-depth.
- **Fix:** add a CSP via
  `plug :put_secure_browser_headers, %{"content-security-policy" => "..."}` or
  in the Caddyfile. The root-layout inline theme script needs a nonce or a
  `sha256-` hash in `script-src` (or move it to a static `.js` file served
  from `priv/static` so `script-src 'self'` covers it). Start report-only if
  unsure, then enforce.
  - Note the map hook loads raster tiles from `*.basemaps.cartocdn.com` and
    maplibre workers/blobs — `img-src`, `worker-src`/`child-src blob:`, and
    `connect-src` need to allow those.
- **Acceptance:** CSP present on HTML responses; map, tiles, timeline, filters,
  and LiveView socket all still work with no console CSP violations.

### SEC-4 — `force_ssl` Host-based redirect/HSTS bypass · LOW

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`config/prod.exs`](../config/prod.exs) `force_ssl:` →
  `exclude: [hosts: ["localhost", "127.0.0.1"]]`
- **Problem:** a request carrying a spoofed `Host: localhost` header skips the
  HTTPS redirect and the HSTS header. Low impact here (Caddy terminates TLS
  regardless; no auth cookies), but there's no reason to keep it for an
  internet deployment.
- **Fix:** set `force_ssl: [rewrite_on: [:x_forwarded_proto], exclude: []]`.
  The old `exclude: [hosts: [...]]` was also just wrong shape for `Plug.SSL`
  (its `:exclude` is a flat host list / fun), and `Plug.SSL` *defaults*
  `:exclude` to `["localhost", "127.0.0.1"]` — so an explicit `[]` is needed
  to actually stop honouring a spoofed `Host: localhost`.
- **Acceptance:** `curl -H 'Host: localhost' http://<server>/` returns a 301 to
  https and https responses carry `strict-transport-security`. **Verified**
  against the local prod stack: `Host: localhost` + `x-forwarded-proto: http`
  now 301s (was 200 before), and other hosts already did.

### SEC-5 — Query-injection landmine in TigerWeb · LOW (not web-reachable today)

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`lib/flockademic/regions/tiger_web.ex`](../lib/flockademic/regions/tiger_web.ex)
  `fetch_state/1`, `fetch_counties/1` — `where: "STUSAB='#{stusab}'"` and
  `where: "STATE='#{state_fips}'"` interpolated into the ArcGIS query string
- **Problem:** only callable from a console today (`import_state("GA")`), so
  not exploitable over HTTP. But if it's ever wired to a request param it's an
  injection into the upstream Census API query.
- **Fix:** validate `stusab` against `~r/\A[A-Za-z]{2}\z/` (and upcase) before
  interpolating; `state_fips` comes from the Census response so lower risk, but
  a `~r/\A\d{2}\z/` guard is cheap. Add a `# not user input` note either way.
- **Acceptance:** `import_state("GA' OR '1'='1")` raises/returns an error
  instead of building a query.

### SEC-6 — No rate limiting on `/api/cameras.geojson` · LOW

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`lib/flockademic_web/controllers/camera_geo_json_controller.ex`](../lib/flockademic_web/controllers/camera_geo_json_controller.ex)
  / [`lib/flockademic_web/router.ex`](../lib/flockademic_web/router.ex) `:api`
  scope
- **Problem:** ~30MB response. ETS-cached so cheap to *produce*, but repeated
  requests are a bandwidth/CPU (gzip) amplifier with no throttle.
- **Fix:** add a `rate_limit` directive in the Caddyfile for `/api/*`, or a
  `PlugAttack`/`Hammer`-based throttle plug on the `:api` pipeline. Also
  confirm Caddy is the one gzipping (it is, per the controller moduledoc) and
  cap concurrent connections at the proxy.
- **Acceptance:** a tight request loop against the endpoint gets 429s after a
  reasonable threshold; normal map usage is unaffected.

### SEC-7 — CARTO API key quota theft · INFO

- **Status:** [ ] **operator action** — no code change; do this in the CARTO dashboard
- **Where:** [`assets/js/hooks/map.js`](../assets/js/hooks/map.js),
  [`config/runtime.exs`](../config/runtime.exs) `:carto_api_key`
- **Problem:** correctly treated as non-secret (sent with every tile request),
  but anyone can scrape it and burn the 5M-tiles/month free quota.
- **Fix:** in the CARTO dashboard, restrict the key to the deployment's
  domain(s) via allowed HTTP referrers. No code change needed.
- **Acceptance:** the key returns tiles when referred from the production
  domain and is rejected elsewhere.

---

## Hygiene / process

### SEC-8 — `example.env` placeholder secrets · INFO

- **Status:** [x] done (branch `security-hardening`)
- **Where:** [`example.env`](../example.env)
- **Problem:** ships `SECRET_KEY_BASE=change-me-generate-a-real-64-byte-secret`
  and `POSTGRES_PASSWORD=change-me`. `SECRET_KEY_BASE` is enforced at compose
  level (`:?`); `POSTGRES_PASSWORD` is not (see SEC-1).
- **Fix:** reword the comments to spell out the generation command
  (`mix phx.gen.secret`, `openssl rand -base64 48`) and that the stack must
  refuse to start with placeholder values. Covered partly by SEC-1.

### SEC-9 — Add dependency / static-analysis auditing · INFO

- **Status:** [x] done (branch `security-hardening`) — deps + `precommit` + CI
- **Where:** [`mix.exs`](../mix.exs) deps & `precommit` alias,
  [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)
- **Problem:** no automated check for dependency CVEs or Phoenix-specific
  issues. (Current snapshot is clean — Phoenix 1.8.12, Bandit 1.12.5, Plug
  1.20.3, LiveView 1.2.10 — but that decays.)
- **Fix:** add
  `{:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false}` and
  `{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}`; wire
  `mix deps.audit` and `mix sobelow --config` into the `precommit` alias and
  any CI pipeline.
- **Acceptance:** `mix deps.audit` and `mix sobelow` run green in `precommit`.

### SEC-10 — Automatic migrations on container start · INFO

- **Status:** [x] no change needed — acceptable for single-container deploys (documented here)
- **Where:** [`docker/entrypoint.sh`](../docker/entrypoint.sh)
- **Problem:** `Flockademic.Release.migrate()` runs on every container start.
  Fine for a single container; if the app is ever scaled to >1 replica, two
  starting at once can race on the migration lock (Ecto's advisory lock
  usually handles this, but it's worth being deliberate).
- **Fix:** acceptable as-is for single-container deploys — document that
  assumption here. If scaling horizontally later, move migrations to a
  one-shot job / init container instead of the app entrypoint.

---

## Reviewed and OK (no action)

- No injection in the web request path — all Ecto queries parameterized;
  `region_id` flows through `Repo.get!` with primary-key casting.
- No XSS — HEEx auto-escapes; no `raw/1`, `innerHTML`,
  `dangerouslySetInnerHTML`. JS hooks only read `dataset` / checkbox values.
- No command execution, dynamic atoms from input, or `binary_to_term`.
- CSRF protection on; `check_origin` defaults on in prod (validates against
  `PHX_HOST`) so LiveView websockets are CSWSH-protected.
- LiveDashboard + Swoosh mailbox gated behind compile-time `dev_routes` — not
  in the prod build.
- Dockerfile: multi-stage, pinned slim base, non-root `flockademic` user,
  `SECRET_KEY_BASE` / `DATABASE_URL` hard-required at runtime, `.env` excluded
  via `.dockerignore`.
- `.env` is gitignored and untracked; only `example.env` is committed.
