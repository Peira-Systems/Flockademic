defmodule Flockademic.Cameras do
  @moduledoc """
  The Cameras context: documented ALPR cameras and the observations that
  evidence them.
  """

  import Ecto.Query, warn: false
  alias Flockademic.Repo
  alias Flockademic.Cameras.{Camera, Observation}

  def list_cameras, do: Repo.all(Camera)

  def get_camera!(id), do: Repo.get!(Camera, id)

  def count_cameras, do: Repo.aggregate(Camera, :count)

  @doc "Distinct, non-nil manufacturer values, for the filters panel."
  def distinct_manufacturers do
    Repo.all(
      from c in Camera,
        where: not is_nil(c.manufacturer),
        distinct: true,
        order_by: c.manufacturer,
        select: c.manufacturer
    )
  end

  @doc "Distinct, non-nil camera_type values, for the filters panel."
  def distinct_camera_types do
    Repo.all(
      from c in Camera,
        where: not is_nil(c.camera_type),
        distinct: true,
        order_by: c.camera_type,
        select: c.camera_type
    )
  end

  @doc """
  Camera points as a GeoJSON `FeatureCollection`, for one-shot delivery to
  the map (see MapLive).
  """
  def cameras_geojson do
    %{type: "FeatureCollection", features: Enum.map(list_cameras(), &to_geojson_feature/1)}
  end

  @doc "Builds one GeoJSON `Feature` from a `Camera` (used by MapLive and Regions)."
  def to_geojson_feature(camera) do
    %{
      type: "Feature",
      geometry: %{type: "Point", coordinates: [camera.longitude, camera.latitude]},
      properties: %{
        id: camera.id,
        manufacturer: camera.manufacturer,
        camera_type: camera.camera_type,
        first_observed_at: camera.first_observed_at,
        direction: direction(camera)
      }
    }
  end

  @doc """
  OSM's `direction` tag is a compass bearing in degrees (0 = north),
  present for some but not all cameras. Comes through as a raw string in
  the tags blob stored as `Camera.metadata`.
  """
  def direction(%Camera{metadata: %{"direction" => direction}}) when is_binary(direction) do
    case Float.parse(direction) do
      {degrees, _} -> degrees
      :error -> nil
    end
  end

  def direction(_camera), do: nil

  @doc """
  A camera plus everything needed for its detail panel: the observations
  that evidence it (provenance) and the nearest other documented camera.
  """
  def get_camera_detail!(id) do
    camera = get_camera!(id)

    %{
      camera: camera,
      observations: list_observations(camera),
      nearest_other: nearest_other_camera(camera)
    }
  end

  def list_observations(camera) do
    Repo.all(from o in Observation, where: o.camera_id == ^camera.id, order_by: o.observed_at)
  end

  @doc """
  The nearest *other* documented camera to `camera`, with the distance in
  meters (via PostGIS's `<->` KNN operator, which uses the GiST index).

  With only one ingestion snapshot to date, every camera's
  `first_observed_at` is nearly identical, so this is spatial nearest-
  neighbor only — NOT evidence that the other camera came "before" this
  one. Project.md is explicit that nearest-neighbor must never be
  presented as a causal/temporal claim; callers should label this
  "nearest documented camera," not "nearest previously observed."
  """
  def nearest_other_camera(camera) do
    query =
      from c in Camera,
        where: c.id != ^camera.id,
        order_by: fragment("? <-> ?", c.geom, ^camera.geom),
        limit: 1,
        select: {c, fragment("ST_Distance(?::geography, ?::geography)", c.geom, ^camera.geom)}

    case Repo.one(query) do
      nil -> nil
      {other, distance_meters} -> %{camera: other, distance_meters: distance_meters}
    end
  end

  @doc """
  Idempotently records that `source` documented a camera (`source_id`) at
  `source_record_id` as of `observed_at`. Running the same snapshot twice
  must not create duplicate cameras or observations (Project.md, Data
  Ingestion).

  `attrs` requires: source, source_id, source_record_id, latitude,
  longitude, observed_at — plus any optional Camera/Observation fields
  (manufacturer, operator, camera_type, metadata, ...).
  """
  def ingest_observation(attrs) do
    result =
      Repo.transaction(fn ->
        camera = upsert_camera(attrs)

        case insert_observation(camera, attrs) do
          {:ok, _observation} -> camera
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    # The single write path every ingestion source funnels through, so
    # this is the one place camera-derived caches need invalidating — the
    # GeoJSON responses (GeoJSONCache) and the /analytics region rankings
    # (Regions.RankingsCache). See each module's moduledoc.
    with {:ok, _camera} <- result do
      Flockademic.Cameras.GeoJSONCache.invalidate()
      Flockademic.Regions.RankingsCache.invalidate()
    end

    result
  end

  defp upsert_camera(attrs) do
    observed_at = Map.fetch!(attrs, :observed_at)

    case Repo.get_by(Camera, source: attrs.source, source_id: attrs.source_id) do
      nil ->
        %Camera{}
        |> Camera.changeset(
          Map.merge(attrs, %{first_observed_at: observed_at, last_observed_at: observed_at})
        )
        |> Repo.insert!()

      camera ->
        camera
        |> Camera.changeset(%{
          first_observed_at: earlier(camera.first_observed_at, observed_at),
          last_observed_at: later(camera.last_observed_at, observed_at)
        })
        |> Repo.update!()
    end
  end

  defp insert_observation(camera, attrs) do
    %Observation{}
    |> Observation.changeset(Map.put(attrs, :camera_id, camera.id))
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:source, :source_record_id])
  end

  defp earlier(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)
  defp later(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
end
