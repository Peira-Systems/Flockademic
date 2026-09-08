defmodule Flockademic.Ingest.Scheduler do
  @moduledoc """
  Periodically re-runs the live Overpass adapter (`Flockademic.Ingest.OSM`)
  against one US state/territory per tick, cycling through all of them
  over time, then recomputes region snapshots — Project.md's "Phase 5 —
  Production ingestion" (scheduled snapshot collection), built on the
  live adapter since it needs no Docker/osmium/manual file downloads.

  Runs one region per tick rather than the whole country at once because
  the shared public Overpass instance rate-limits hard well below the
  size of a single US state (see `Flockademic.Ingest.OSM`'s moduledoc) —
  `Flockademic.Ingest.run_grid/3` already tiles+delays within one region,
  but sweeping all 50+ regions back-to-back in one process would still
  hammer the shared instance. Spreading them across ticks keeps every
  individual run polite while still refreshing the whole dataset over a
  full cycle. A slow region (e.g. a large state with many tiles) simply
  pushes the next tick back rather than overlapping with it, since the
  next tick is only scheduled after the current one finishes.

  Region bounding boxes come from `Flockademic.Regions` (already-imported
  state boundaries) for the 50 states + DC, plus two hardcoded entries for
  Puerto Rico and the US Virgin Islands, which TIGERweb import doesn't
  cover but which do have real documented ALPR cameras (see the
  "Nationwide ingestion" section of the README — Geofabrik's `us-latest
  .osm.pbf` silently excludes both territories, which is what this
  scheduler exists to stop from recurring unnoticed).

  Disabled by default (see `enabled?/0`) so dev/test never fires against
  the shared public API unannounced.
  """

  use GenServer
  require Logger

  alias Flockademic.{Ingest, Regions}

  @default_interval_ms :timer.hours(24)

  # Approximate {south, west, north, east} boxes — good enough for a
  # periodic top-up sweep, not the authoritative source (that's the bulk
  # Geofabrik/osmium path in `Flockademic.Ingest.OSMExtract`'s moduledoc).
  # A camera right on a boundary might be missed by one region's box and
  # picked up by a neighbor's, or vice versa — idempotent ingestion means
  # that never creates duplicates either way.
  @territories [
    {"Puerto Rico", {17.4, -67.5, 18.6, -65.1}},
    {"US Virgin Islands", {17.6, -65.1, 18.5, -64.5}}
  ]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Whether the scheduler should run at all. Off by default — set
  `config :flockademic, Flockademic.Ingest.Scheduler, enabled: true`
  (or `SCHEDULED_INGEST_ENABLED=true` in prod, see config/runtime.exs) to
  turn it on.
  """
  def enabled? do
    :flockademic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, false)
  end

  @impl true
  def init(opts) do
    if enabled?() do
      state = %{
        regions: Keyword.get_lazy(opts, :regions, &default_regions/0),
        index: 0,
        interval_ms: Keyword.get(opts, :interval_ms, configured_interval_ms()),
        ingest_fun: Keyword.get(opts, :ingest_fun, &default_ingest/1)
      }

      schedule_tick(state.interval_ms)
      {:ok, state}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:tick, %{regions: []} = state) do
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  def handle_info(:tick, state) do
    {name, bbox} = Enum.at(state.regions, state.index)

    case state.ingest_fun.(bbox) do
      %{ingested: count, failed_tiles: []} ->
        Logger.info("[Flockademic.Ingest.Scheduler] #{name}: #{count} camera(s) observed")

      %{ingested: count, failed_tiles: failed} ->
        Logger.warning(
          "[Flockademic.Ingest.Scheduler] #{name}: #{count} camera(s) observed, " <>
            "#{length(failed)} tile(s) failed"
        )
    end

    stats = Regions.compute_daily_snapshots()
    Phoenix.PubSub.broadcast(Flockademic.PubSub, "camera_updates", {:snapshot_complete, stats})

    schedule_tick(state.interval_ms)
    {:noreply, %{state | index: rem(state.index + 1, length(state.regions))}}
  end

  defp schedule_tick(interval_ms), do: Process.send_after(self(), :tick, interval_ms)

  defp configured_interval_ms do
    :flockademic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:interval_ms, @default_interval_ms)
  end

  defp default_ingest(bbox), do: Ingest.run_grid(Ingest.OSM, bbox)

  defp default_regions do
    state_regions =
      "state"
      |> Regions.list_regions_by_type()
      |> Enum.map(fn region ->
        %{south: south, west: west, north: north, east: east} = Regions.bounds(region)
        {region.name, {south, west, north, east}}
      end)

    state_regions ++ @territories
  end
end
