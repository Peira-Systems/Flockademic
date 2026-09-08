defmodule Flockademic.CamerasTest do
  use Flockademic.DataCase, async: true

  alias Flockademic.Cameras

  @attrs %{
    source: "osm",
    source_id: "node/1",
    source_record_id: "node/1@2026-01-01",
    latitude: 39.1,
    longitude: -84.5,
    observed_at: ~U[2026-01-01 00:00:00Z]
  }

  test "ingest_observation/1 creates a camera and an observation" do
    assert {:ok, camera} = Cameras.ingest_observation(@attrs)
    assert camera.source == "osm"
    assert camera.first_observed_at == @attrs.observed_at
    assert camera.last_observed_at == @attrs.observed_at
    assert Cameras.count_cameras() == 1
  end

  test "ingest_observation/1 is idempotent: the same snapshot record twice creates no duplicates" do
    assert {:ok, camera} = Cameras.ingest_observation(@attrs)
    assert {:ok, camera_again} = Cameras.ingest_observation(@attrs)

    assert camera.id == camera_again.id
    assert Cameras.count_cameras() == 1
    assert Repo.aggregate(Flockademic.Cameras.Observation, :count) == 1
  end

  test "ingest_observation/1 widens first/last_observed_at without overwriting the earlier bound" do
    assert {:ok, _camera} = Cameras.ingest_observation(@attrs)

    later = %{
      @attrs
      | source_record_id: "node/1@2026-06-01",
        observed_at: ~U[2026-06-01 00:00:00Z]
    }

    assert {:ok, camera} = Cameras.ingest_observation(later)
    assert camera.first_observed_at == ~U[2026-01-01 00:00:00Z]
    assert camera.last_observed_at == ~U[2026-06-01 00:00:00Z]
    assert Cameras.count_cameras() == 1
    assert Repo.aggregate(Flockademic.Cameras.Observation, :count) == 2
  end
end
