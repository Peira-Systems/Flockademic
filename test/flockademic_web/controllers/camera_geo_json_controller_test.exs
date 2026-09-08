defmodule FlockademicWeb.CameraGeoJSONControllerTest do
  use FlockademicWeb.ConnCase, async: true

  alias Flockademic.{Cameras, Regions}

  defp camera_fixture(attrs) do
    base = %{source: "osm", observed_at: ~U[2026-01-01 00:00:00Z]}
    {:ok, camera} = attrs |> Enum.into(base) |> Cameras.ingest_observation()
    camera
  end

  test "GET /api/cameras.geojson returns every camera as a FeatureCollection", %{conn: conn} do
    camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})
    camera_fixture(%{source_id: "b", source_record_id: "b@1", latitude: 40.0, longitude: -75.0})

    conn = get(conn, ~p"/api/cameras.geojson")

    assert %{"type" => "FeatureCollection", "features" => features} = json_response(conn, 200)
    assert length(features) == 2
  end

  test "GET /api/cameras.geojson?region_id=X returns only cameras inside that region", %{
    conn: conn
  } do
    {:ok, region} =
      Regions.upsert_region_boundary(%{
        type: "state",
        name: "Testland",
        fips: "99",
        geom: %Geo.Polygon{
          coordinates: [
            [{-85.0, 33.0}, {-85.0, 34.0}, {-84.0, 34.0}, {-84.0, 33.0}, {-85.0, 33.0}]
          ],
          srid: 4326
        }
      })

    inside =
      camera_fixture(%{
        source_id: "in",
        source_record_id: "in@1",
        latitude: 33.5,
        longitude: -84.5
      })

    camera_fixture(%{
      source_id: "out",
      source_record_id: "out@1",
      latitude: 40.0,
      longitude: -75.0
    })

    conn = get(conn, ~p"/api/cameras.geojson", region_id: region.id)

    assert %{"features" => [feature]} = json_response(conn, 200)
    assert feature["properties"]["id"] == inside.id
  end

  test "returns an ETag, and a matching If-None-Match gets a 304 with no body", %{conn: conn} do
    camera_fixture(%{source_id: "a", source_record_id: "a@1", latitude: 33.5, longitude: -84.5})

    conn = get(conn, ~p"/api/cameras.geojson")
    assert [etag] = get_resp_header(conn, "etag")
    json_response(conn, 200)

    conn =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> get(~p"/api/cameras.geojson")

    assert conn.status == 304
    assert conn.resp_body == ""
  end
end
