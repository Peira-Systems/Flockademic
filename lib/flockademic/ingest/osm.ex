defmodule Flockademic.Ingest.OSM do
  @moduledoc """
  Source adapter for OpenStreetMap ALPR nodes tagged the way the
  DeFlock/FlockHopper project tags them (`surveillance:type=ALPR`), fetched
  from the public Overpass API.

  This is the "Initial Source" from Project.md's ingestion architecture.
  Only the current live dataset is available this way — reconstructing
  history requires either repeated snapshots over time or imported archival
  data (see Project.md, "Historical Dataset").
  """

  @behaviour Flockademic.Ingest.Source

  @default_overpass_url "https://overpass-api.de/api/interpreter"

  @doc """
  Fetches every `surveillance:type=ALPR` node inside `opts[:bbox]`, a
  `{south, west, north, east}` tuple of WGS84 degrees.

  `opts[:overpass_url]` overrides the Overpass instance queried — the
  default public instance is often overloaded; alternate public mirrors
  include `https://overpass.kumi.systems/api/interpreter`.
  """
  @impl true
  def fetch(opts \\ []) do
    {south, west, north, east} = Keyword.fetch!(opts, :bbox)
    url = Keyword.get(opts, :overpass_url, @default_overpass_url)
    query = overpass_query(south, west, north, east)

    case Req.post(url,
           form: [data: query],
           receive_timeout: 60_000,
           connect_options: [timeout: 10_000]
         ) do
      {:ok, %{status: 200, body: %{"elements" => elements}}} ->
        {:ok, Enum.map(elements, &normalize/1)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp overpass_query(south, west, north, east) do
    """
    [out:json][timeout:60];
    node["surveillance:type"="ALPR"](#{south},#{west},#{north},#{east});
    out body;
    """
  end

  defp normalize(%{"id" => id, "lat" => lat, "lon" => lon} = element) do
    tags = Map.get(element, "tags", %{})
    Flockademic.Ingest.OSMTags.normalize(id, lat, lon, tags)
  end
end
