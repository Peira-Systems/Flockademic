import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# The camera-derived caches (Flockademic.Cameras.GeoJSONCache and
# Flockademic.Regions.RankingsCache) are process-global ETS tables, which
# don't play well with Ecto Sandbox's per-test isolation — async tests would
# otherwise see each other's cached data. Disabled here; each lookup falls
# back to querying directly instead.
config :flockademic, Flockademic.Cameras.GeoJSONCache, enabled: false
config :flockademic, Flockademic.Regions.RankingsCache, enabled: false

config :flockademic, Flockademic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "flockademic_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :flockademic, FlockademicWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "rEf8Eo3OaJacV6AyrKCqtJfRVY+IqY+aPwbyjHENLpO0Fh2X2hjJh3SQMu9ifpRi",
  server: false

# In test we don't send emails
config :flockademic, Flockademic.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
