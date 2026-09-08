#!/bin/sh
set -eu

echo "Running database migrations..."
/app/bin/flockademic eval "Flockademic.Release.migrate()"

exec "$@"
