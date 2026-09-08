defmodule Flockademic.RegionsTest do
  use Flockademic.DataCase, async: true

  alias Flockademic.{Cameras, Regions}

  # A 1x1 degree square roughly covering part of Georgia — real-shaped
  # test data, not degenerate geometry.
  @square %Geo.Polygon{
    coordinates: [[{-85.0, 33.0}, {-85.0, 34.0}, {-84.0, 34.0}, {-84.0, 33.0}, {-85.0, 33.0}]],
    srid: 4326
  }

  defp region_fixture(attrs \\ %{}) do
    {:ok, region} =
      Regions.upsert_region_boundary(
        Map.merge(%{type: "state", name: "Testland", fips: "99", geom: @square}, attrs)
      )

    region
  end

  defp camera_fixture(attrs) do
    base = %{
      source: "osm",
      observed_at: ~U[2026-01-01 00:00:00Z]
    }

    {:ok, camera} = attrs |> Enum.into(base) |> Cameras.ingest_observation()
    camera
  end

  describe "cameras_in_region/1" do
    test "returns only cameras whose point falls inside the boundary" do
      region = region_fixture()

      inside =
        camera_fixture(%{source_id: "in", source_record_id: "in@1", latitude: 33.5, longitude: -84.5})

      camera_fixture(%{source_id: "out", source_record_id: "out@1", latitude: 40.0, longitude: -84.5})

      assert [found] = Regions.cameras_in_region(region)
      assert found.id == inside.id
    end
  end

  describe "region_stats/1" do
    test "computes real totals from current camera data" do
      region = region_fixture()

      camera_fixture(%{
        source_id: "a",
        source_record_id: "a@1",
        latitude: 33.5,
        longitude: -84.5,
        observed_at: ~U[2026-01-01 00:00:00Z]
      })

      stats = Regions.region_stats(region)
      assert stats.total_cameras == 1
      assert stats.first_observed_at == ~U[2026-01-01 00:00:00Z]
    end

    test "growth_rate is nil with fewer than two snapshots (never fabricated)" do
      region = region_fixture()
      assert Regions.region_stats(region).growth_rate == nil

      Regions.compute_snapshot(region, ~D[2026-01-01])
      assert Regions.region_stats(region).growth_rate == nil
    end

    test "growth_rate is real once two snapshots exist" do
      region = region_fixture()

      camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})
      Regions.compute_snapshot(region, ~D[2026-01-01])

      camera_fixture(%{source_id: "b", source_record_id: "b@1", latitude: 33.6, longitude: -84.5})
      Regions.compute_snapshot(region, ~D[2026-01-02])

      stats = Regions.region_stats(region)
      # 1 camera -> 2 cameras between the two snapshots = +100%
      assert_in_delta stats.growth_rate, 1.0, 0.0001
    end
  end

  describe "camera_growth_index/3" do
    test "is nil when nothing was known before the window (no baseline to divide by)" do
      now = ~U[2026-06-01 00:00:00Z]

      cameras = [
        %{first_observed_at: ~U[2026-05-20 00:00:00Z]},
        %{first_observed_at: ~U[2026-05-25 00:00:00Z]}
      ]

      assert Regions.camera_growth_index(cameras, now, 30) == nil
    end

    test "is a real ratio when there's a baseline" do
      now = ~U[2026-06-01 00:00:00Z]

      cameras = [
        # known before the 30-day window started
        %{first_observed_at: ~U[2026-01-01 00:00:00Z]},
        %{first_observed_at: ~U[2026-01-01 00:00:00Z]},
        # new during the window
        %{first_observed_at: ~U[2026-05-25 00:00:00Z]}
      ]

      # 1 new / 2 known-at-start = 0.5
      assert Regions.camera_growth_index(cameras, now, 30) == 0.5
    end
  end

  describe "region_rankings/1" do
    test "orders regions by total documented cameras, descending" do
      {:ok, sparse} =
        Regions.upsert_region_boundary(%{
          type: "county",
          name: "Sparse County",
          fips: "99001",
          geom: @square
        })

      dense_square = %Geo.Polygon{
        coordinates: [
          [{-90.0, 40.0}, {-90.0, 41.0}, {-89.0, 41.0}, {-89.0, 40.0}, {-90.0, 40.0}]
        ],
        srid: 4326
      }

      {:ok, dense} =
        Regions.upsert_region_boundary(%{
          type: "county",
          name: "Dense County",
          fips: "99002",
          geom: dense_square
        })

      camera_fixture(%{source_id: "s1", source_record_id: "s1@1", latitude: 33.5, longitude: -84.5})
      camera_fixture(%{source_id: "d1", source_record_id: "d1@1", latitude: 40.5, longitude: -89.5})
      camera_fixture(%{source_id: "d2", source_record_id: "d2@1", latitude: 40.6, longitude: -89.5})

      [first, second] = Regions.region_rankings("county")

      assert first.region.id == dense.id
      assert first.total_cameras == 2
      assert second.region.id == sparse.id
      assert second.total_cameras == 1
    end
  end
end
