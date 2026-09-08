defmodule Flockademic.Ingest.OSMExtract do
  @moduledoc """
  Source adapter for a *bulk* regional/planet OSM extract, pre-filtered to
  ALPR nodes and exported to GeoJSON with `osmium` — the production path
  for comprehensive coverage that doesn't hammer the shared public
  Overpass API (see Project.md, "Data Ingestion" / "ingestion reliability").

  This does NOT fetch or shell out to anything itself — it only reads a
  GeoJSON file you've already produced, keeping the pipeline testable and
  free of a hard runtime dependency on Docker/osmium being installed.

  ## Producing the input file

  Given a regional extract (e.g. from https://download.geofabrik.de/),
  filter it to ALPR nodes and export with real OSM ids AND each node's own
  edit timestamp/version preserved:

      osmium tags-filter -o alpr.osm.pbf region.osm.pbf n/surveillance:type=ALPR
      osmium export -c export-config.json -o alpr.geojson alpr.osm.pbf

  where `export-config.json` is
  `{"attributes": {"id": true, "version": true, "timestamp": true}}`.
  (Newer osmium-tool accepts `-a id,version,timestamp` directly; verify
  against your installed version rather than assuming.) `changeset`/`uid`/
  `user` are deliberately not requested — Geofabrik's public extracts strip
  them (they've been personal-data-gated to the password-protected
  internal server since 2018-05-03), so they'd come back empty anyway.

  Each feature's OSM node id/version/timestamp are expected as
  `properties["@id"]`/`["@version"]`/`["@timestamp"]`, matching osmium's
  own attribute-export convention. `@timestamp` comes out as Unix epoch
  seconds (an integer), not an ISO 8601 string — confirmed empirically
  against real `osmium export` output, so don't assume otherwise if you're
  changing the parsing.

  ## Why per-node timestamp, not one batch date

  A node's `@timestamp` is when it was last edited in OSM — for the ~50%+
  of ALPR nodes still at `@version` 1, that's also its creation date, i.e.
  a real, camera-specific `first_observed_at` instead of "when I got
  around to loading this file" (or even "when the extract was generated")
  applied identically to every camera in the batch. For edited nodes
  (`@version` > 1) it's an upper bound, not an exact creation date — true
  creation requires the full edit history, not this current-state extract.
  """

  @behaviour Flockademic.Ingest.Source

  @doc """
  Reads `opts[:path]` (a GeoJSON FeatureCollection) and normalizes every
  feature, using each feature's own `properties["@timestamp"]` as its
  `observed_at` when present. `opts[:observed_at]` is the fallback used for
  features without one (e.g. a file exported without `timestamp` in
  `export-config.json`) — pass the extract's own `osm_base` timestamp for
  that fallback when you have it, since that's still a better fact than
  the moment this function happens to run.
  """
  # sobelow_skip ["Traversal.FileModule"]
  # `path` is an operator-supplied local file path — this adapter is only
  # invoked from `bin/flockademic rpc 'Flockademic.Release.ingest(...)'` (see
  # Flockademic.Release), never from web input.
  @impl true
  def fetch(opts \\ []) do
    path = Keyword.fetch!(opts, :path)
    fallback_observed_at = Keyword.get(opts, :observed_at, DateTime.utc_now())

    with {:ok, contents} <- File.read(path),
         {:ok, %{"features" => features}} <- Jason.decode(contents) do
      {:ok, Enum.map(features, &normalize(&1, fallback_observed_at))}
    else
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_geojson, error}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize(
         %{"geometry" => %{"coordinates" => [lon, lat]}, "properties" => properties},
         fallback_observed_at
       ) do
    {id, properties} = Map.pop(properties, "@id")
    {version, properties} = Map.pop(properties, "@version")
    {timestamp, tags} = Map.pop(properties, "@timestamp")

    observed_at = parse_timestamp(timestamp) || fallback_observed_at

    id
    |> Flockademic.Ingest.OSMTags.normalize(lat, lon, tags, observed_at)
    |> put_osm_version(version)
  end

  defp parse_timestamp(nil), do: nil

  # osmium's GeoJSON writer emits `@timestamp` as Unix epoch seconds, not an
  # ISO 8601 string (confirmed empirically against real `osmium export`
  # output — don't assume otherwise).
  defp parse_timestamp(timestamp) when is_integer(timestamp) do
    case DateTime.from_unix(timestamp) do
      {:ok, datetime} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp put_osm_version(record, nil), do: record

  defp put_osm_version(record, version) do
    update_in(record, [:metadata], &Map.put(&1 || %{}, "osm_version", version))
  end
end
