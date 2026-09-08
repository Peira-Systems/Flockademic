# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :flockademic,
  ecto_repos: [Flockademic.Repo],
  generators: [timestamp_type: :utc_datetime]

# The explorer (Polars) precompiled NIF defaults to a build that assumes
# modern CPU features (e.g. AVX2). On hosts without them it crashes at
# runtime with "Illegal instruction" rather than failing to compile, so
# opt into the legacy-CPU artifact only where EXPLORER_USE_LEGACY_ARTIFACTS
# is set (e.g. our self-hosted Docker build host) — read at compile time,
# so it must be set before `mix deps.compile`.
# https://github.com/elixir-explorer/explorer#legacy-cpus
config :explorer, use_legacy_artifacts: System.get_env("EXPLORER_USE_LEGACY_ARTIFACTS") == "true"

# Use the PostGIS-aware Postgrex type module so geometry/geography
# columns (Geo.PostGIS.Geometry) can be read/written through Ecto.
config :flockademic, Flockademic.Repo, types: Flockademic.PostgresTypes

# Configure the endpoint
config :flockademic, FlockademicWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FlockademicWeb.ErrorHTML, json: FlockademicWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Flockademic.PubSub,
  live_view: [signing_salt: "pYVDRgue"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r",
  # Windows without an elevated terminal can't create the node_modules
  # symlink colocated assets use; we don't import from assets/node_modules
  # in colocated hooks, so this is safe to silence.
  colocated_assets: [disable_symlink_warning: true]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :flockademic, Flockademic.Mailer, adapter: Swoosh.Adapters.Local

# Off by default in every environment — dev/test must never fire against
# the shared public Overpass API unannounced. See
# Flockademic.Ingest.Scheduler's moduledoc; config/runtime.exs turns this
# on for prod via SCHEDULED_INGEST_ENABLED.
config :flockademic, Flockademic.Ingest.Scheduler, enabled: false

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  flockademic: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  # maplibre-gl processes GeoJSON sources in a Web Worker it loads from a
  # separate file (via `new Worker(new URL(...), {type: "module"})`).
  # esbuild's main bundle doesn't emit that file automatically the way
  # webpack/rollup plugins do, so we bundle it ourselves and point
  # maplibre at the result with `maplibregl.setWorkerUrl(...)` in map.js.
  # Without this, GeoJSON-backed layers silently never render — the
  # worker script 404s (falling through to Phoenix's HTML error page),
  # and the browser rejects it as a module script.
  flockademic_worker: [
    args:
      ~w(node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs --bundle --format=esm --outfile=../priv/static/assets/js/maplibre-gl-worker.js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  flockademic: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
