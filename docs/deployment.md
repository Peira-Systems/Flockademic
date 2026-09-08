# Deployment

The app is deployed as a Docker Compose stack (`app` + `db` + `caddy`) on a
single host. Images are built and pushed to a self-hosted, HTTPS container
registry, then rolled out to the server over SSH.

**Build and deploy are manual** — run from a trusted machine, not from CI.
This repo is public, so the registry and production-SSH credentials are
deliberately kept out of GitHub Actions. CI ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml))
runs only the test job (compile with warnings as errors, `mix_audit`,
`sobelow`, `mix test`) on every push and PR.

> An automated pipeline (self-hosted `build-and-push` + `deploy` jobs using
> `appleboy/scp-action` + `appleboy/ssh-action`) ran here until 2026-09-08,
> when the repo went public and the jobs were removed. If CD comes back it
> should live in a private repo or behind a protected environment.

## Build and push images

From a machine with Docker and registry credentials, at the repo root:

```bash
export REGISTRY=<registry host>            # e.g. registry.example.com
export IMAGE_NAME=flockademic              # the one provisioned repo; the
                                          # registry doesn't auto-create repos
SHORT_SHA=$(git rev-parse --short HEAD)

echo "<REGISTRY_PASSWORD>" | docker login "$REGISTRY" -u "<REGISTRY_USER>" --password-stdin

# App image (Phoenix release)
docker build --pull --build-arg EXPLORER_USE_LEGACY_ARTIFACTS=true \
  -t "$REGISTRY/$IMAGE_NAME:$SHORT_SHA" -t "$REGISTRY/$IMAGE_NAME:latest" .

# Caddy image (stock caddy + ratelimit module + baked-in Caddyfile). Ships in
# the same repo under `caddy-`-prefixed tags.
docker build --pull -f docker/caddy/Dockerfile \
  -t "$REGISTRY/$IMAGE_NAME:caddy-$SHORT_SHA" -t "$REGISTRY/$IMAGE_NAME:caddy-latest" .

docker push "$REGISTRY/$IMAGE_NAME:$SHORT_SHA"
docker push "$REGISTRY/$IMAGE_NAME:latest"
docker push "$REGISTRY/$IMAGE_NAME:caddy-$SHORT_SHA"
docker push "$REGISTRY/$IMAGE_NAME:caddy-latest"
docker logout "$REGISTRY"
```

Then copy [`docker-compose.deploy.yml`](../docker-compose.deploy.yml) and
[`scripts/refresh-data.sh`](../scripts/refresh-data.sh) to the host and roll
the stack over — see **Deploy / rollback** below.

## One-time host setup

Do this once on the deploy host before the first deploy. The deploy user must
be in the `docker` group and own `/opt/flockademic` (deploys run no `sudo`).

### 1. Create the deployment directory and secrets file

```bash
sudo mkdir -p /opt/flockademic && sudo chown "$USER:$USER" /opt/flockademic
```

Create `/opt/flockademic/.env` (root-owned, `chmod 600`) from
[`example.env`](../example.env), with **real** values:

```
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<openssl rand -base64 36>
POSTGRES_DB=flockademic_prod
POSTGRES_DATA_DIR=./data/postgres

SECRET_KEY_BASE=<openssl rand -base64 48>
POOL_SIZE=10

CARTO_API_KEY=<the CARTO basemap key>

DOMAIN=<real, publicly-resolvable hostname; ports 80/443 reachable>
ACME_EMAIL=<ops email for Let's Encrypt>

CAMERA_DATA_DIR=./data/cameras
SCHEDULED_INGEST_ENABLED=false
SCHEDULED_INGEST_INTERVAL_MS=86400000
```

Do **not** copy `docker-compose.override.yml` to the host — it re-publishes the
Postgres port (local-dev only, see SEC-1).

### 2. Verify registry access

The registry is served over HTTPS with a publicly-trusted cert, so no
`insecure-registries` entry or `/etc/hosts` change is needed — the host just
needs to resolve and reach it:

```bash
REGISTRY=<registry host>
echo "<REGISTRY_PASSWORD>" | docker login "$REGISTRY" -u "<REGISTRY_USER>" --password-stdin
docker pull "$REGISTRY/flockademic:latest"
```

## Loading and refreshing data

A freshly deployed stack has empty tables — the map and `/analytics` show
nothing until region boundaries and camera data are loaded. Copy
[`scripts/refresh-data.sh`](../scripts/refresh-data.sh) to the host as
`/opt/flockademic/refresh-data.sh` and run it there (stack must be up).

```bash
cd /opt/flockademic

# First-time full load: Census boundaries + the whole US OSM ALPR extract
# (+ PR / USVI). Downloads ~11 GB, runs osmium, ~tens of minutes — use tmux.
./refresh-data.sh --regions --bulk

# Just (re)import region boundaries (states + counties)
./refresh-data.sh --regions
./refresh-data.sh --regions --states "GA FL"

# Ingest a GeoJSON extract you've dropped in ./data/cameras/
./refresh-data.sh --file alpr.geojson

# Periodic camera refresh (re-run the bulk extract; ingestion is idempotent)
./refresh-data.sh --bulk

# Turn the Overpass top-up scheduler on/off (one state per tick over time,
# see Flockademic.Ingest.Scheduler) — complements a periodic --bulk run
./refresh-data.sh --scheduler on
```

Under the hood each step is a `bin/flockademic rpc` call
(`Flockademic.Release.import_regions/1`, `.ingest/1`) — `--bulk` additionally
shells out to `docker run stefda/osmium-tool` to build the GeoJSON. See
[README.md](../README.md) "Ingesting camera data" for the data model details
and the territory caveat.

## Deploy / rollback

After pushing images (see **Build and push images** above), copy the compose
file and data script to the host and bring the stack up:

```bash
# from a machine with SSH access to the host
scp docker-compose.deploy.yml <user>@<host>:/opt/flockademic/docker-compose.yml
scp scripts/refresh-data.sh   <user>@<host>:/opt/flockademic/refresh-data.sh

ssh <user>@<host>
cd /opt/flockademic
export REGISTRY=<registry host>          # required, not kept in .env
# roll out latest, or pin/roll back to a specific commit's image:
echo "IMAGE_TAG=<short-sha>" >> .env     # omit to track `latest`; or edit the line
docker compose pull
docker compose up -d --remove-orphans
docker compose ps                        # confirm db / app / caddy are running
```

Migrations run automatically on `app` container start
(`docker/entrypoint.sh`, see SEC-10). `docker-compose.deploy.yml` reads
`IMAGE_TAG` (default `latest`) and `REGISTRY` (**required, no default**).

## Networking / TLS

Caddy obtains a Let's Encrypt cert for `$DOMAIN` on first start via the ACME
HTTP-01 / TLS-ALPN-01 challenge, so **ports 80 and 443 must be reachable from
the public internet** on the host. If the host is behind NAT, forward 80 and
443 to it on the router (SSH/22 being forwarded is not enough). Symptom of a
missing forward, in `docker compose logs caddy`:

```
challenge failed ... "detail":"<public-ip>: Timeout during connect (likely firewall problem)"
```

Caddy keeps retrying, but after a few failures it backs off for a long
interval — if the forward was added late, force an immediate retry with
`docker compose restart caddy` (on the host, in `/opt/flockademic`).

## Post-deploy checks (first launch)

From the security review (`docs/security-hardening.md`):

- `nmap -p 5432 <host>` from outside → closed (SEC-1)
- concurrent load on `/analytics` leaves the map responsive (SEC-2)
- map + tiles + timeline load over the real cert with no console CSP errors (SEC-3)
- `curl -H 'Host: localhost' http://<host>/` → 301 to https (SEC-4)
- restrict the CARTO key by HTTP referrer in the CARTO dashboard (SEC-7)
