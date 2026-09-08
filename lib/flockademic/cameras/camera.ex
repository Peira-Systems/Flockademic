defmodule Flockademic.Cameras.Camera do
  @moduledoc """
  A documented ALPR camera.

  `first_observed_at` is the earliest date Flockademic can demonstrate the
  camera existed in one of its source datasets — it is NOT an installation
  date. `installed_at` stays nil unless a source specifically establishes an
  install/deployment date. See Project.md, "Critical Temporal Rule".
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "cameras" do
    field :source, :string
    field :source_id, :string
    field :manufacturer, :string
    field :operator, :string
    field :camera_type, :string
    field :latitude, :float
    field :longitude, :float
    field :geom, Geo.PostGIS.Geometry

    field :first_observed_at, :utc_datetime
    field :last_observed_at, :utc_datetime
    field :installed_at, :utc_datetime
    field :installed_at_source, :string
    field :installed_at_confidence, :string

    field :metadata, :map, default: %{}

    has_many :observations, Flockademic.Cameras.Observation

    timestamps(type: :utc_datetime)
  end

  @required ~w(source source_id latitude longitude first_observed_at last_observed_at)a
  @optional ~w(manufacturer operator camera_type installed_at installed_at_source installed_at_confidence metadata)a

  def changeset(camera, attrs) do
    camera
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> put_geom()
    |> unique_constraint([:source, :source_id], error_key: :source_id)
  end

  defp put_geom(changeset) do
    with lat when not is_nil(lat) <- get_field(changeset, :latitude),
         lng when not is_nil(lng) <- get_field(changeset, :longitude) do
      put_change(changeset, :geom, %Geo.Point{coordinates: {lng, lat}, srid: 4326})
    else
      _ -> changeset
    end
  end
end
