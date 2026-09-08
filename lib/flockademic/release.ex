defmodule Flockademic.Release do
  @moduledoc """
  Tasks for running in a compiled release, where `mix` isn't available —
  invoked as `bin/flockademic eval "Flockademic.Release.migrate()"` (see
  `docker/entrypoint.sh`, which runs `migrate/0` on every container start).
  """

  @app :flockademic

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # 50 states + DC. The Census TIGERweb service has no "all states" call, so
  # `import_regions/1` just loops. Territories (PR, USVI) aren't in TIGERweb's
  # State_County service — see `Flockademic.Ingest.Scheduler`'s moduledoc.
  @us_states ~w(AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME
                MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI
                SC SD TN TX UT VT VA WA WV WI WY)

  @doc """
  Imports (or refreshes) US state + county boundary polygons from the Census
  TIGERweb service. These back the region filter on the map and the
  `/analytics` rankings, so a fresh database needs this before either shows
  anything. Idempotent — rows are matched by FIPS. Pass a subset of
  two-letter codes to limit it, e.g. `import_regions(~w(GA FL))`.

  Invoke with `rpc` (it needs the running node's Repo + HTTP client):

      bin/flockademic rpc 'Flockademic.Release.import_regions()'
  """
  def import_regions(codes \\ @us_states) do
    results =
      Enum.map(codes, fn code ->
        case Flockademic.Regions.TigerWeb.import_state(code) do
          {:ok, %{counties: counties}} ->
            IO.puts("#{code}: ok (#{length(counties)} counties)")
            {code, :ok}

          other ->
            IO.puts("#{code}: FAILED — #{inspect(other)}")
            {code, :error}
        end
      end)

    failed = for {code, :error} <- results, do: code
    ok = length(results) - length(failed)
    IO.puts("\nimported #{ok}/#{length(results)} states")
    if failed != [], do: IO.puts("failed: #{Enum.join(failed, ", ")}")
    if failed == [], do: :ok, else: {:error, failed}
  end

  @doc """
  Ingests a GeoJSON extract (see `Flockademic.Ingest.OSMExtract`'s
  moduledoc for how to produce the file, and README.md's "Ingesting
  camera data" section) and recomputes region snapshots. Invoke with
  `rpc`, not `eval`:

      bin/flockademic rpc 'Flockademic.Release.ingest("/data/cameras/alpr.geojson")'

  `rpc` runs this *inside* the already-running release, where
  `Flockademic.Application`'s supervision tree (Repo, and
  `Flockademic.Cameras.GeoJSONCache`, whose cache this ingest needs to
  invalidate) is already up. `eval` boots a separate, throwaway node that
  never starts that tree — this would either crash reaching for a cache
  table that doesn't exist there, or, worse, silently invalidate a copy
  of the cache the live server never sees, leaving it stale.
  """
  def ingest(path) do
    {:ok, results} = Flockademic.Ingest.run(Flockademic.Ingest.OSMExtract, path: path)
    ok_count = Enum.count(results, &match?({:ok, _}, &1))
    IO.puts("Ingested #{ok_count}/#{length(results)} records from #{path}")

    stats = Flockademic.Regions.compute_daily_snapshots()
    IO.inspect(stats, label: "region snapshots recomputed")
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
  end
end
