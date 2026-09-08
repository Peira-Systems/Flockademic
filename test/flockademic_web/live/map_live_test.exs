defmodule FlockademicWeb.MapLiveTest do
  use FlockademicWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Flockademic.{Cameras, Regions}

  setup do
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

    {:ok, camera} =
      Cameras.ingest_observation(%{
        source: "osm",
        source_id: "node/1",
        source_record_id: "node/1@2026-01-01",
        latitude: 33.5,
        longitude: -84.5,
        observed_at: ~U[2026-01-01 00:00:00Z],
        manufacturer: "Flock Safety"
      })

    %{region: region, camera: camera}
  end

  test "mounts and shows the camera count", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "known by this date"
  end

  test "selecting a state shows real region stats", %{conn: conn, region: region} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> form("form[phx-change='state:selected']", %{state_id: region.id})
      |> render_change()

    assert html =~ region.name
    assert html =~ "Documented cameras"
  end

  test "clicking a camera (as the map hook would) shows its detail and provenance", %{
    conn: conn,
    camera: camera
  } do
    {:ok, view, _html} = live(conn, "/")

    html = render_hook(view, "camera:clicked", %{"id" => to_string(camera.id)})

    assert html =~ "Camera ##{camera.id}"
    assert html =~ "Flock Safety"
    assert html =~ "Provenance"
    assert html =~ "node/1@2026-01-01"
  end

  test "closing the camera panel clears it", %{conn: conn, camera: camera} do
    {:ok, view, _html} = live(conn, "/")
    render_hook(view, "camera:clicked", %{"id" => to_string(camera.id)})

    html =
      view
      |> element("button[phx-click='camera:close']")
      |> render_click()

    refute html =~ "Provenance"
  end
end
