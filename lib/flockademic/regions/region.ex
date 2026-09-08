defmodule Flockademic.Regions.Region do
  @moduledoc """
  A geographic area (country, state, county, or municipality) used to
  scope statistics and the camera-density map.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(country state county municipality)

  schema "regions" do
    field :type, :string
    field :name, :string
    field :fips, :string
    field :geom, Geo.PostGIS.Geometry

    timestamps(type: :utc_datetime)
  end

  def changeset(region, attrs) do
    region
    |> cast(attrs, [:type, :name, :fips, :geom])
    |> validate_required([:type, :name])
    |> validate_inclusion(:type, @types)
  end
end
