defmodule Flockademic.Ingest.OSMTags do
  @moduledoc """
  Shared normalization from a raw OSM node (id/lat/lon/tags) into the attrs
  shape `Flockademic.Cameras.ingest_observation/1` expects. Used by both
  `Flockademic.Ingest.OSM` (live Overpass queries) and
  `Flockademic.Ingest.OSMExtract` (bulk regional/planet file processing)
  so the two sources can never silently disagree on field derivation.
  """

  alias Flockademic.Ingest.{CameraType, Manufacturer}

  @doc """
  `observed_at` defaults to now — pass an explicit value when normalizing
  records pulled from a dated bulk extract rather than a live query.
  """
  def normalize(id, lat, lon, tags, observed_at \\ DateTime.utc_now()) do
    today = DateTime.to_date(observed_at)

    %{
      source: "osm",
      source_id: "node/#{id}",
      source_record_id: "node/#{id}@#{today}",
      latitude: lat,
      longitude: lon,
      observed_at: observed_at,
      manufacturer: manufacturer(tags),
      operator: Map.get(tags, "operator"),
      camera_type: tags |> Map.get("surveillance") |> CameraType.normalize(),
      metadata: tags
    }
  end

  # OSM taggers use `manufacturer` and `brand` fairly interchangeably for
  # this purpose — falling back to `brand` when `manufacturer` is absent
  # recovers a real value for ~4,400 cameras that would otherwise show as
  # unknown despite the source actually naming a manufacturer.
  defp manufacturer(tags) do
    (Map.get(tags, "manufacturer") || Map.get(tags, "brand"))
    |> Manufacturer.normalize()
  end
end
