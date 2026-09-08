defmodule Flockademic.Cameras.GeoJSONCacheTest do
  # async: false — flips the cache on globally for this module (it's
  # disabled by default in :test, see config/test.exs), so it can't run
  # concurrently with other tests hitting the same ETS table/config.
  use Flockademic.DataCase, async: false

  alias Flockademic.Cameras
  alias Flockademic.Cameras.GeoJSONCache

  setup do
    Application.put_env(:flockademic, GeoJSONCache, enabled: true)
    GeoJSONCache.invalidate()

    on_exit(fn ->
      Application.put_env(:flockademic, GeoJSONCache, enabled: false)
      GeoJSONCache.invalidate()
    end)

    :ok
  end

  defp camera_fixture(attrs) do
    base = %{source: "osm", observed_at: ~U[2026-01-01 00:00:00Z]}
    {:ok, camera} = attrs |> Enum.into(base) |> Cameras.ingest_observation()
    camera
  end

  test "repeated calls return the identical cached payload" do
    camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})

    {json1, etag1} = GeoJSONCache.all()
    {json2, etag2} = GeoJSONCache.all()

    assert json1 == json2
    assert etag1 == etag2
  end

  test "ingesting a camera invalidates the cache so the next read reflects it" do
    camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})
    {json_before, etag_before} = GeoJSONCache.all()
    assert %{"features" => [_one]} = Jason.decode!(json_before)

    camera_fixture(%{source_id: "b", source_record_id: "b@1", latitude: 40.0, longitude: -75.0})
    {json_after, etag_after} = GeoJSONCache.all()

    assert %{"features" => [_, _]} = Jason.decode!(json_after)
    refute etag_after == etag_before
  end
end
