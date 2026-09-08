defmodule Flockademic.Regions.RankingsCache do
  @moduledoc """
  Caches the result of `Flockademic.Regions.region_rankings/1` in ETS.

  `region_rankings/1` runs a multi-second nationwide spatial join (~3,100
  counties × ~136k cameras — see its docs) and is hit on *every* `/analytics`
  page load, unauthenticated. Without caching, a handful of concurrent loads
  each tie up a DB connection for the duration; with `POOL_SIZE` defaulting to
  10 that's enough to starve the rest of the app (a cheap denial of service).

  The rankings only change when camera data changes, so the cache is
  invalidated wholesale by `Flockademic.Cameras.ingest_observation/1` — the
  single write path every ingestion source funnels through (same mechanism as
  `Flockademic.Cameras.GeoJSONCache`). Region *boundaries* changing
  (`Flockademic.Regions.TigerWeb` imports, a rare manual console op) aren't
  hooked; call `invalidate/0` by hand after a boundary import if it matters.

  Disabled in `:test` (see `enabled?/0`) for the same reason as
  `GeoJSONCache`: a process-global ETS table doesn't play well with Ecto
  Sandbox's per-test isolation.
  """

  use GenServer

  alias Flockademic.Regions

  @table __MODULE__

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Cached rankings for a region type (\"state\" or \"county\")."
  def rankings(type), do: fetch(type, fn -> Regions.region_rankings(type) end)

  @doc """
  Drops every cached entry. Safe to call when the cache is disabled/empty or
  when this node never started it (e.g. `bin/flockademic eval`) — a no-op
  there rather than a crash.
  """
  def invalidate do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  def enabled? do
    :flockademic
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    # Warm the common case (county rankings, what /analytics loads) so the
    # first visitor isn't the one paying the multi-second rebuild. Non-blocking
    # so app boot doesn't wait on it; skipped when disabled since the DB may
    # not be safely queryable in that context (see moduledoc — :test boot).
    if enabled?(), do: Task.start(fn -> rankings("county") end)

    {:ok, %{}}
  end

  defp fetch(key, compute) do
    if enabled?() do
      case :ets.lookup(@table, key) do
        [{^key, value}] ->
          value

        [] ->
          value = compute.()
          :ets.insert(@table, {key, value})
          value
      end
    else
      compute.()
    end
  end
end
