#!/usr/bin/env bash
#
# Refresh Flockademic's data: Census region boundaries + OSM ALPR cameras.
#
# Run it ON the deploy host, from the compose project directory
# (default /opt/flockademic — copy this script there, see docs/deployment.md).
# The stack must already be up.
#
# Usage:
#   ./refresh-data.sh --regions [--states "GA FL"]
#       (Re)import state + county boundaries from the Census TIGERweb API.
#       Needed once on a fresh DB before the map filter / analytics work.
#
#   ./refresh-data.sh --file alpr.geojson
#       Ingest a GeoJSON extract you've already placed in ./data/cameras/.
#
#   ./refresh-data.sh --bulk
#       Download the full US OSM extract (+ Puerto Rico, US Virgin Islands),
#       filter to ALPR nodes with osmium, and ingest. Needs Docker, ~20 GB
#       free disk under ./data/cameras, and downloads ~11 GB from Geofabrik.
#       Slow (tens of minutes) — run under tmux/screen or with nohup.
#
#   ./refresh-data.sh --scheduler on|off
#       Flip SCHEDULED_INGEST_ENABLED in .env and recreate the app container.
#       The scheduler tops up from Overpass one state per tick over time
#       (see Flockademic.Ingest.Scheduler) — complements, doesn't replace,
#       a periodic --bulk run.
#
# Flags combine, e.g. a full first-time load:
#   ./refresh-data.sh --regions --bulk
#
set -euo pipefail

PROJECT_DIR="${FLOCKADEMIC_DIR:-/opt/flockademic}"
OSM_IMAGE="${OSM_IMAGE:-stefda/osmium-tool}"
GEOFABRIK="https://download.geofabrik.de/north-america"
# {geofabrik path : human label}
EXTRACTS=(
  "us-latest.osm.pbf|continental US + DC"
  "us/puerto-rico-latest.osm.pbf|Puerto Rico"
  "us/us-virgin-islands-latest.osm.pbf|US Virgin Islands"
)
MIN_FREE_GB=20

do_regions=0
do_file=""
do_bulk=0
states=""
scheduler=""

[ $# -gt 0 ] || { sed -n '3,40p' "$0"; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    --regions)     do_regions=1 ;;
    --states)      states="${2:?--states needs a value}"; shift ;;
    --file)        do_file="${2:?--file needs a value}"; shift ;;
    --bulk)        do_bulk=1 ;;
    --scheduler)   scheduler="${2:?--scheduler needs on|off}"; shift ;;
    --dir)         PROJECT_DIR="${2:?--dir needs a path}"; shift ;;
    -h|--help)     sed -n '3,40p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$PROJECT_DIR"
compose() { docker compose "$@"; }
rpc() { compose exec -T app bin/flockademic rpc "$1"; }

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ./data/cameras is often created root-owned by Docker on first `up` (it's a
# bind-mount source). Take ownership so this script — and you, dropping a
# --file extract in — can write there without sudo on every call.
ensure_cameras_dir() {
  if [ ! -d data/cameras ] || [ ! -w data/cameras ]; then
    sudo mkdir -p data/cameras
    sudo chown "$(id -u):$(id -g)" data/cameras
  fi
}

# Run osmium as the invoking user so extract files stay writable by this
# script (default container root would leave root-owned junk in $work).
DRUN=(docker run --rm --user "$(id -u):$(id -g)")

log "Flockademic data refresh — $(date -u +%FT%TZ) — project $PROJECT_DIR"
compose exec -T app true 2>/dev/null || {
  echo "app container is not running — 'docker compose up -d' first" >&2
  exit 1
}

if [ "$do_regions" = 1 ]; then
  if [ -n "$states" ]; then
    codes=$(printf '"%s",' $states); codes="[${codes%,}]"
    log "Importing Census region boundaries for: $states"
  else
    codes=""
    log "Importing Census region boundaries (50 states + DC)"
  fi
  rpc "Flockademic.Release.import_regions(${codes})"
fi

if [ -n "$do_file" ]; then
  ensure_cameras_dir
  test -f "data/cameras/$do_file" || { echo "no such file: data/cameras/$do_file" >&2; exit 1; }
  log "Ingesting data/cameras/$do_file"
  rpc "Flockademic.Release.ingest(\"/data/cameras/$do_file\")"
fi

if [ "$do_bulk" = 1 ]; then
  ensure_cameras_dir
  avail_gb=$(df -BG --output=avail data/cameras | tail -1 | tr -dc '0-9')
  if [ "${avail_gb:-0}" -lt "$MIN_FREE_GB" ]; then
    echo "only ${avail_gb}G free under data/cameras, need ~${MIN_FREE_GB}G" >&2
    exit 1
  fi

  work="$PWD/data/cameras/.extract.$$"
  mkdir -p "$work"
  trap 'rm -rf "$work"' EXIT
  echo '{"attributes":{"id":true,"version":true,"timestamp":true}}' > "$work/export-config.json"

  for entry in "${EXTRACTS[@]}"; do
    path="${entry%%|*}"; label="${entry#*|}"
    base="$(basename "$path")"
    log "Fetching + filtering $label"
    curl -fL --retry 3 --retry-delay 5 -o "$work/$base" "$GEOFABRIK/$path"
    "${DRUN[@]}" -v "$work:/w" "$OSM_IMAGE" \
      osmium tags-filter --overwrite -o "/w/${base%.osm.pbf}.alpr.pbf" \
      "/w/$base" n/surveillance:type=ALPR
    rm -f "$work/$base"
  done

  log "Merging + exporting to GeoJSON"
  "${DRUN[@]}" -v "$work:/w" "$OSM_IMAGE" sh -ceu '
    files=$(ls /w/*.alpr.pbf)
    if [ "$(echo "$files" | wc -l)" -gt 1 ]; then
      osmium merge --overwrite $files -o /w/alpr.merged.pbf
    else
      cp $files /w/alpr.merged.pbf
    fi
    osmium export --overwrite -c /w/export-config.json -o /w/alpr.geojson /w/alpr.merged.pbf
  '

  out="data/cameras/alpr-$(date -u +%Y%m%d).geojson"
  mv "$work/alpr.geojson" "$out"
  rm -rf "$work"; trap - EXIT
  log "Ingesting $(basename "$out")"
  rpc "Flockademic.Release.ingest(\"/data/cameras/$(basename "$out")\")"
fi

if [ -n "$scheduler" ]; then
  case "$scheduler" in
    on)  val=true ;;
    off) val=false ;;
    *) echo "--scheduler takes 'on' or 'off'" >&2; exit 2 ;;
  esac
  log "Setting SCHEDULED_INGEST_ENABLED=$val"
  if grep -q '^SCHEDULED_INGEST_ENABLED=' .env; then
    sed -i "s/^SCHEDULED_INGEST_ENABLED=.*/SCHEDULED_INGEST_ENABLED=$val/" .env
  else
    echo "SCHEDULED_INGEST_ENABLED=$val" >> .env
  fi
  compose up -d app
fi

log "Done. Current counts:"
rpc 'IO.puts("cameras:  " <> Integer.to_string(Flockademic.Cameras.count_cameras()))
     IO.puts("regions:  " <> Integer.to_string(length(Flockademic.Regions.list_regions_by_type("state"))) <> " states")'
