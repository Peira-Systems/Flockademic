defmodule Flockademic.Regions do
  @moduledoc """
  The Regions context: geographic areas (state/county) used to scope
  statistics, plus their precomputed historical snapshots.

  Real boundaries come from the Census Bureau's TIGERweb service (see
  `Flockademic.Regions.TigerWeb`) — "region" here always means an actual
  administrative boundary, never an approximation.
  """

  import Ecto.Query, warn: false
  import Geo.PostGIS, only: [st_contains: 2]

  alias Flockademic.Repo
  alias Flockademic.Cameras
  alias Flockademic.Cameras.Camera
  alias Flockademic.Regions.{Region, RegionSnapshot}

  def list_regions, do: Repo.all(Region)

  def list_regions_by_type(type), do: Repo.all(from r in Region, where: r.type == ^type, order_by: r.name)

  @doc """
  Counties belonging to `state`, for the county picker. Filters by FIPS
  prefix in SQL (Census GEOID scheme: a county's FIPS is the state's
  two-digit FIPS plus a county suffix) and selects only `id`/`name`
  rather than the full `Region` — the picker doesn't need boundary
  geometry, and fetching + WKB-decoding every county nationwide just to
  filter them client-side (what `list_regions_by_type("county")` would
  do here) is the exact cost `region_rankings/1` warns about, and was
  slow enough to time out the state-select event.
  """
  def list_counties_in_state(%Region{type: "state", fips: state_fips}) do
    Repo.all(
      from r in Region,
        where: r.type == "county" and like(r.fips, ^"#{state_fips}%"),
        order_by: r.name,
        select: %{id: r.id, name: r.name}
    )
  end

  def get_region!(id), do: Repo.get!(Region, id)

  def create_region(attrs) do
    %Region{}
    |> Region.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Idempotently inserts or updates a region boundary (state/county) keyed by
  its Census `fips`/GEOID. Used by `Flockademic.Regions.TigerWeb`.
  """
  def upsert_region_boundary(attrs) do
    %Region{}
    |> Region.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:type, :name, :geom, :updated_at]},
      conflict_target: [:fips]
    )
  end

  def upsert_region_snapshot(attrs) do
    %RegionSnapshot{}
    |> RegionSnapshot.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:camera_count, :new_camera_count, :camera_density, :growth_rate]},
      conflict_target: [:region_id, :date]
    )
  end

  def list_region_snapshots(region) do
    Repo.all(from s in RegionSnapshot, where: s.region_id == ^region.id, order_by: s.date)
  end

  @doc """
  Computes and stores *today's* real statistics for every region as a
  `RegionSnapshot`. Meant to run once per day (e.g. after each ingestion
  run) so growth trends accumulate real history over time — this only
  ever records what's true right now, never a backfilled/fabricated past
  value (Project.md: never fabricate missing historical dates).

  Does the whole spatial join + aggregation as one SQL query rather than
  iterating `compute_snapshot/2` per region — with ~3,100 regions
  nationwide, fetching each one's full polygon into Elixir just to hand
  it straight back to Postgres in a follow-up query hit the exact same
  WKB-decoding cost that made `region_rankings/1` time out (see there).
  """
  def compute_daily_snapshots(date \\ Date.utc_today()) do
    query =
      from(r in Region,
        left_join: c in Camera,
        on: st_contains(r.geom, c.geom),
        group_by: r.id,
        select: %{
          region_id: r.id,
          total_cameras: count(c.id),
          new_today: fragment("count(*) FILTER (WHERE ?::date = ?)", c.first_observed_at, ^date),
          area_sq_meters: fragment("ST_Area(?::geography)", r.geom)
        }
      )

    # The nested-loop spatial join (one index scan per region) measured at
    # ~11-13s for the full nationwide dataset (3,195 regions) — reasonable
    # for a once-a-day background job, but close enough to Ecto's default
    # 15s query timeout to intermittently trip it under concurrent load
    # (confirmed: a `bin/flockademic rpc`-triggered run hit
    # DBConnection.ConnectionError, "checked out the connection for
    # longer than 15000ms"). Explicit generous headroom here rather than
    # raising the app-wide default.
    Repo.all(query, timeout: 60_000)
    |> Enum.map(fn row ->
      area_sq_miles = row.area_sq_meters && row.area_sq_meters / 2_589_988.110336
      density = if area_sq_miles && area_sq_miles > 0, do: row.total_cameras / area_sq_miles

      upsert_region_snapshot(%{
        region_id: row.region_id,
        date: date,
        camera_count: row.total_cameras,
        new_camera_count: row.new_today,
        camera_density: density
      })
    end)
  end

  def compute_snapshot(region, date \\ Date.utc_today()) do
    cameras = cameras_in_region(region)
    total = length(cameras)

    new_today =
      Enum.count(cameras, fn c ->
        c.first_observed_at && DateTime.to_date(c.first_observed_at) == date
      end)

    area = area_sq_miles(region)
    density = if area && area > 0, do: total / area, else: nil

    upsert_region_snapshot(%{
      region_id: region.id,
      date: date,
      camera_count: total,
      new_camera_count: new_today,
      camera_density: density
    })
  end

  @doc "All cameras whose point geometry falls inside `region`'s boundary."
  def cameras_in_region(region) do
    Repo.all(from c in Camera, where: st_contains(^region.geom, c.geom))
  end

  @doc """
  GeoJSON `FeatureCollection` of camera points inside `region`, in the same
  shape as `Flockademic.Cameras.cameras_geojson/0` — used to re-focus the
  map on a region without resending the entire national dataset.
  """
  def region_cameras_geojson(region) do
    features = region |> cameras_in_region() |> Enum.map(&Cameras.to_geojson_feature/1)
    %{type: "FeatureCollection", features: features}
  end

  @doc "The `{south, west, north, east}`-shaped bounding box of `region`'s boundary."
  def bounds(region) do
    query =
      from r in Region,
        where: r.id == ^region.id,
        select: %{
          south: fragment("ST_YMin(?)", r.geom),
          west: fragment("ST_XMin(?)", r.geom),
          north: fragment("ST_YMax(?)", r.geom),
          east: fragment("ST_XMax(?)", r.geom)
        }

    Repo.one(query)
  end

  @doc """
  Area of `region`'s boundary in square miles, computed geodetically
  (cast to `geography`) rather than in raw degrees.
  """
  def area_sq_miles(region) do
    query = from r in Region, where: r.id == ^region.id, select: fragment("ST_Area(?::geography)", r.geom)

    case Repo.one(query) do
      nil -> nil
      square_meters -> square_meters / 2_589_988.110336
    end
  end

  @doc """
  Live statistics for `region`, computed directly from current camera data
  (not from precomputed snapshots — those are for historical trend charts).

  `growth_rate` and `peak_growth_period` require at least two days of
  `RegionSnapshot` history to mean anything; both are `nil` until then
  rather than a fabricated number (Project.md: never fake missing history).
  """
  def region_stats(region) do
    cameras = cameras_in_region(region)
    total = length(cameras)
    now = DateTime.utc_now()

    first_observed_at =
      case cameras do
        [] -> nil
        _ -> cameras |> Enum.map(& &1.first_observed_at) |> Enum.min(DateTime)
      end

    new_30d = Enum.count(cameras, &within_days?(&1.first_observed_at, now, 30))
    new_1y = Enum.count(cameras, &within_days?(&1.first_observed_at, now, 365))

    area = area_sq_miles(region)
    density = if area && area > 0, do: total / area, else: nil

    snapshots = list_region_snapshots(region)

    %{
      total_cameras: total,
      first_observed_at: first_observed_at,
      new_observations_30d: new_30d,
      new_observations_1y: new_1y,
      area_sq_miles: area,
      camera_density: density,
      camera_growth_index_30d: camera_growth_index(cameras, now, 30),
      growth_rate: growth_rate(snapshots),
      peak_growth_period: peak_growth_period(snapshots),
      snapshot_count: length(snapshots)
    }
  end

  @doc """
  Camera Growth Index over the trailing `window_days`:

      new cameras observed during window / cameras known at start of window

  Returns `nil` when there's no baseline to divide by (no cameras were
  already known before the window started) — with only one ingestion
  snapshot to date, this is `nil` almost everywhere, honestly.
  """
  def camera_growth_index(cameras, now \\ DateTime.utc_now(), window_days \\ 30) do
    window_start = DateTime.add(now, -window_days * 86_400, :second)

    known_at_start =
      Enum.count(cameras, &(DateTime.compare(&1.first_observed_at, window_start) == :lt))

    new_during_window = length(cameras) - known_at_start

    if known_at_start > 0, do: new_during_window / known_at_start, else: nil
  end

  defp within_days?(nil, _now, _days), do: false
  defp within_days?(observed_at, now, days), do: DateTime.diff(now, observed_at, :day) <= days

  # Percent change between the earliest and latest recorded snapshot.
  # Needs 2+ real snapshots — see RegionSnapshot; not fabricated from
  # today's single ingestion run.
  defp growth_rate([_single]), do: nil
  defp growth_rate([]), do: nil

  defp growth_rate(snapshots) do
    first = List.first(snapshots)
    last = List.last(snapshots)

    if first.camera_count > 0 do
      (last.camera_count - first.camera_count) / first.camera_count
    else
      nil
    end
  end

  defp peak_growth_period(snapshots) when length(snapshots) < 2, do: nil

  defp peak_growth_period(snapshots) do
    snapshots
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.max_by(fn [a, b] -> b.new_camera_count - a.new_camera_count end, fn -> nil end)
    |> case do
      [a, b] -> {a.date, b.date}
      nil -> nil
    end
  end

  @doc """
  Ranks regions of `type` ("state" | "county") by total documented camera
  count and density, computed with a single spatial join query rather than
  N+1 per-region lookups.

  Selects only `id`/`name` for each region rather than the full `Region`
  struct — nationwide, boundary polygons run into the thousands of
  coordinate pairs each, and decoding ~3,000 of them from WKB client-side
  (which fetching the full struct would do) took over a minute even
  though the underlying SQL query itself runs in ~1s. Same reasoning for
  computing area in the same aggregate query instead of one `ST_Area`
  round-trip per region.

  Growth-based rankings (fastest-growing, largest absolute increase) need
  multiple days of `RegionSnapshot` history — until that accumulates, this
  ranks by current totals/density only, which is the honest thing it can
  say today.
  """
  def region_rankings(type) do
    from(r in Region,
      left_join: c in Camera,
      on: st_contains(r.geom, c.geom),
      where: r.type == ^type,
      group_by: r.id,
      select: %{
        id: r.id,
        name: r.name,
        total_cameras: count(c.id),
        area_sq_meters: fragment("ST_Area(?::geography)", r.geom)
      },
      order_by: [desc: count(c.id)]
    )
    # Same nested-loop spatial join as compute_daily_snapshots/1 (see its
    # comment) — measured at ~3.6s for "county" nationwide uncontended,
    # comfortably under Ecto's default 15s timeout normally, but this
    # runs on every /analytics page load (via assign_async — see
    # AnalyticsLive's moduledoc), so the same generous headroom is worth
    # it against occasional contention rather than surfacing an
    # avoidable error to a user.
    |> Repo.all(timeout: 60_000)
    |> Enum.map(fn row ->
      area_sq_miles = row.area_sq_meters && row.area_sq_meters / 2_589_988.110336
      density = if area_sq_miles && area_sq_miles > 0, do: row.total_cameras / area_sq_miles

      %{
        region: %{id: row.id, name: row.name},
        total_cameras: row.total_cameras,
        camera_density: density
      }
    end)
  end
end
