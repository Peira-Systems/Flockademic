defmodule Flockademic.Cameras.GeoJSONCache do
  @moduledoc """
  Caches the pre-encoded JSON for camera GeoJSON responses (full dataset
  and per-region) in ETS, so a repeat request is a table lookup instead
  of a full `Repo.all(Camera)` + `Enum.map` + `Jason.encode!` of the
  whole camera table — with zero caching, rebuilding the full
  ~136k-camera dataset from scratch measured at ~3s and ~30MB per
  request (see `FlockademicWeb.CameraGeoJSONController`).

  Invalidated wholesale by `Flockademic.Cameras.ingest_observation/1`
  (the single write path every ingestion source funnels through — see
  `Flockademic.Ingest`), so a cache hit never has to touch the database
  to check freshness, and any future write path gets correct
  invalidation for free just by going through `ingest_observation/1`.

  Disabled in `:test` (see `enabled?/0`) — this is a process-global ETS
  table, which doesn't play well with Ecto Sandbox's per-test isolation;
  async tests would otherwise see each other's cached camera data.
  """

  use GenServer

  alias Flockademic.{Cameras, Regions}

  @table __MODULE__

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Cached `{json, etag}` for the full camera dataset."
  def all, do: fetch(:all, &Cameras.cameras_geojson/0)

  @doc "Cached `{json, etag}` for one region's cameras."
  def region(region),
    do: fetch({:region, region.id}, fn -> Regions.region_cameras_geojson(region) end)

  @doc """
  Drops every cached entry. Safe to call even when the cache is
  disabled/empty, or when this process's node never started the cache at
  all (e.g. `bin/flockademic eval`, unlike `rpc`, boots a throwaway node
  without `Flockademic.Application`'s supervision tree — see
  `Flockademic.Release.ingest/1`) — a no-op there rather than a crash.
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

    # Warm the common case (the full dataset) so the first real request
    # isn't the one paying the ~3s rebuild. Non-blocking so app boot
    # doesn't wait on it; skipped when disabled since the DB may not be
    # safely queryable yet in that context (see moduledoc — :test boot).
    if enabled?(), do: Task.start(&all/0)

    {:ok, %{}}
  end

  defp fetch(key, compute) do
    if enabled?() do
      case :ets.lookup(@table, key) do
        [{^key, json, etag}] ->
          {json, etag}

        [] ->
          {json, etag} = build(compute)
          :ets.insert(@table, {key, json, etag})
          {json, etag}
      end
    else
      build(compute)
    end
  end

  defp build(compute) do
    json = Jason.encode!(compute.())
    {json, etag_for(json)}
  end

  defp etag_for(json), do: ~s("#{Base.url_encode64(:crypto.hash(:sha256, json), padding: false)}")
end
