defmodule Flockademic.Regions.TigerWeb do
  @moduledoc """
  Imports real state/county boundary polygons from the US Census Bureau's
  TIGERweb ArcGIS REST service (the Bureau's own authoritative geographic
  boundary service — not a third-party derivative).

  https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/MapServer

  Layer 0 = States, Layer 1 = Counties. Both support GeoJSON output
  directly via `f=geojson`, which we've verified against the live service.
  """

  alias Flockademic.Regions

  @base_url "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/State_County/MapServer"

  @doc """
  Imports the state boundary and all county boundaries for a two-letter
  state abbreviation (e.g. "GA"). Idempotent — re-running updates existing
  rows (matched by `fips`) rather than duplicating them.
  """
  def import_state(stusab) do
    with {:ok, stusab} <- validate_stusab(stusab),
         {:ok, state_feature} <- fetch_state(stusab),
         {:ok, county_features} <- fetch_counties(state_feature) do
      state_region = upsert_region("state", state_feature)
      county_regions = Enum.map(county_features, &upsert_region("county", &1))
      {:ok, %{state: state_region, counties: county_regions}}
    end
  end

  # `stusab` is interpolated straight into the ArcGIS `where=` clause in
  # fetch_state/1. Callers today are all trusted (console / scripts), but
  # validate anyway so this can never become an injection into the Census
  # query if it's ever wired to external input.
  defp validate_stusab(stusab) when is_binary(stusab) do
    up = String.upcase(stusab)
    if up =~ ~r/\A[A-Z]{2}\z/, do: {:ok, up}, else: {:error, :invalid_state_abbreviation}
  end

  defp validate_stusab(_), do: {:error, :invalid_state_abbreviation}

  defp fetch_state(stusab) do
    query = %{
      where: "STUSAB='#{stusab}'",
      outFields: "STATE,STUSAB,NAME,GEOID",
      returnGeometry: true,
      f: "geojson"
    }

    case Req.get("#{@base_url}/0/query", params: query, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"features" => [feature]}}} -> {:ok, feature}
      {:ok, %{status: 200, body: %{"features" => []}}} -> {:error, :state_not_found}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_counties(%{"properties" => %{"STATE" => state_fips}})
       when is_binary(state_fips) do
    query = %{
      where: "STATE='#{state_fips}'",
      outFields: "STATE,COUNTY,NAME,GEOID",
      returnGeometry: true,
      f: "geojson"
    }

    with :ok <- validate_fips(state_fips) do
      case Req.get("#{@base_url}/1/query", params: query, receive_timeout: 60_000) do
        {:ok, %{status: 200, body: %{"features" => features}}} -> {:ok, features}
        {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # `STATE` (a two-digit FIPS code) comes back from the Census state response,
  # not from a caller — but it's interpolated into the `where=` clause above,
  # so guard its format anyway.
  defp validate_fips(fips) do
    if fips =~ ~r/\A\d{2}\z/, do: :ok, else: {:error, :invalid_state_fips}
  end

  defp upsert_region(type, %{"geometry" => geometry, "properties" => properties}) do
    {:ok, geom} = Geo.JSON.decode(geometry)
    geom = %{geom | srid: 4326}

    {:ok, region} =
      Regions.upsert_region_boundary(%{
        type: type,
        name: properties["NAME"],
        fips: properties["GEOID"],
        geom: geom
      })

    region
  end
end
