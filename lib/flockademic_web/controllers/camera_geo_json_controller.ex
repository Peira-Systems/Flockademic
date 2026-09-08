defmodule FlockademicWeb.CameraGeoJSONController do
  @moduledoc """
  Serves camera locations as a plain GeoJSON HTTP response, fetched
  directly by the map's JS hook rather than embedded in the LiveView
  socket payload.

  Project.md is explicit that large geographic data shouldn't be pushed
  wholesale through LiveView — with the bulk-extract ingestion pipeline
  now pulling in tens of thousands of cameras per state, embedding the
  full dataset in every socket connect/region-focus message would bloat
  every LiveView diff. A plain HTTP GET the browser can fetch, cache, and
  have gzipped in transit (handled by the Caddy reverse proxy in front —
  see Dockerfile/Caddyfile) is the right tool here instead.

  The expensive part — querying and JSON-encoding the full ~136k-camera
  dataset — is cached in `Flockademic.Cameras.GeoJSONCache` rather than
  redone on every request; this controller's own job is just ETag-based
  conditional GETs on top of that cache, so a client that already has the
  current payload gets a `304 Not Modified` instead of re-downloading it.
  """

  use FlockademicWeb, :controller

  alias Flockademic.Cameras.GeoJSONCache
  alias Flockademic.Regions

  def index(conn, %{"region_id" => region_id}) do
    respond(conn, GeoJSONCache.region(Regions.get_region!(region_id)))
  end

  def index(conn, _params) do
    respond(conn, GeoJSONCache.all())
  end

  defp respond(conn, {json, etag}) do
    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "no-cache")

    if fresh?(conn, etag) do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, json)
    end
  end

  # `If-None-Match` can carry one or several comma-separated etags.
  defp fresh?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(&(String.trim(&1) == etag))
  end
end
