defmodule Flockademic.Regions.RankingsCacheTest do
  # async: false — flips the cache on globally for this module (it's disabled
  # by default in :test, see config/test.exs), so it can't run concurrently
  # with other tests hitting the same ETS table/config.
  use Flockademic.DataCase, async: false

  alias Flockademic.{Cameras, Regions}
  alias Flockademic.Regions.RankingsCache

  @square %Geo.Polygon{
    coordinates: [[{-85.0, 33.0}, {-85.0, 34.0}, {-84.0, 34.0}, {-84.0, 33.0}, {-85.0, 33.0}]],
    srid: 4326
  }

  setup do
    Application.put_env(:flockademic, RankingsCache, enabled: true)
    RankingsCache.invalidate()

    on_exit(fn ->
      Application.put_env(:flockademic, RankingsCache, enabled: false)
      RankingsCache.invalidate()
    end)

    :ok
  end

  defp county_fixture(fips) do
    {:ok, region} =
      Regions.upsert_region_boundary(%{
        type: "county",
        name: "County #{fips}",
        fips: fips,
        geom: @square
      })

    region
  end

  defp camera_fixture(attrs) do
    base = %{source: "osm", observed_at: ~U[2026-01-01 00:00:00Z]}
    {:ok, camera} = attrs |> Enum.into(base) |> Cameras.ingest_observation()
    camera
  end

  test "repeated calls return the cached result" do
    county_fixture("99001")
    camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})

    assert RankingsCache.rankings("county") == RankingsCache.rankings("county")
    assert [%{total_cameras: 1}] = RankingsCache.rankings("county")
  end

  test "ingesting a camera invalidates the cache so the next read reflects it" do
    county_fixture("99001")
    camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})
    assert [%{total_cameras: 1}] = RankingsCache.rankings("county")

    camera_fixture(%{source_id: "b", source_record_id: "b@1", latitude: 33.6, longitude: -84.6})
    assert [%{total_cameras: 2}] = RankingsCache.rankings("county")
  end
end
