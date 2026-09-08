defmodule Flockademic.Ingest.OSMExtractTest do
  use ExUnit.Case, async: true

  alias Flockademic.Ingest.OSMExtract

  @geojson """
  {"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-84.3424051,33.7788433]},"properties":{"@id":68456701,"camera:type":"fixed","man_made":"surveillance","manufacturer":"Flock Safety","surveillance":"public","surveillance:type":"ALPR"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-84.3782275,33.879867]},"properties":{"@id":69160967,"direction":"180","man_made":"surveillance","operator":"Flock Safety","surveillance:type":"ALPR"}}
  ]}
  """

  # osmium's GeoJSON writer emits `@timestamp` as Unix epoch seconds (not an
  # ISO 8601 string) — 1741947720 = 2025-03-14T10:22:00Z, 1767600000 =
  # 2026-01-05T08:00:00Z.
  @geojson_with_meta """
  {"type":"FeatureCollection","features":[
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-84.3424051,33.7788433]},"properties":{"@id":68456701,"@version":1,"@timestamp":1741947720,"surveillance:type":"ALPR"}},
  {"type":"Feature","geometry":{"type":"Point","coordinates":[-84.3782275,33.879867]},"properties":{"@id":69160967,"@version":3,"@timestamp":1767600000,"surveillance:type":"ALPR"}}
  ]}
  """

  setup do
    path = Path.join(System.tmp_dir!(), "osm_extract_test_#{System.unique_integer([:positive])}.geojson")
    File.write!(path, @geojson)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "normalizes each feature using the real OSM node id from @id", %{path: path} do
    observed_at = ~U[2026-08-22 20:21:28Z]
    assert {:ok, [a, b]} = OSMExtract.fetch(path: path, observed_at: observed_at)

    assert a.source == "osm"
    assert a.source_id == "node/68456701"
    assert a.source_record_id == "node/68456701@2026-08-22"
    assert a.latitude == 33.7788433
    assert a.longitude == -84.3424051
    assert a.observed_at == observed_at
    assert a.manufacturer == "Flock Safety"
    assert a.camera_type == "Public"

    assert b.source_id == "node/69160967"
    assert b.operator == "Flock Safety"
  end

  test "defaults observed_at to now when not given", %{path: path} do
    before = DateTime.utc_now()
    assert {:ok, [record | _]} = OSMExtract.fetch(path: path)
    assert DateTime.compare(record.observed_at, before) != :lt
  end

  test "returns an error for a missing file" do
    assert {:error, :enoent} = OSMExtract.fetch(path: "/nonexistent/path.geojson")
  end

  test "returns an error for invalid JSON", %{path: path} do
    File.write!(path, "not json")
    assert {:error, {:invalid_geojson, %Jason.DecodeError{}}} = OSMExtract.fetch(path: path)
  end

  test "uses each feature's own @timestamp as its observed_at" do
    path = write_fixture(@geojson_with_meta)
    assert {:ok, [a, b]} = OSMExtract.fetch(path: path)

    assert a.observed_at == ~U[2025-03-14 10:22:00Z]
    assert a.metadata["osm_version"] == 1

    assert b.observed_at == ~U[2026-01-05 08:00:00Z]
    assert b.metadata["osm_version"] == 3
  end

  test "falls back to opts[:observed_at] for features without @timestamp", %{path: path} do
    fallback = ~U[2026-08-22 20:21:28Z]
    assert {:ok, [record | _]} = OSMExtract.fetch(path: path, observed_at: fallback)
    assert record.observed_at == fallback
  end

  defp write_fixture(contents) do
    path = Path.join(System.tmp_dir!(), "osm_extract_test_#{System.unique_integer([:positive])}.geojson")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
