defmodule Flockademic.Regions.RegionSnapshot do
  @moduledoc """
  Precomputed statistics for a region at a point in time, so historical
  animation and charts don't require aggregating raw observations on read.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "region_snapshots" do
    belongs_to :region, Flockademic.Regions.Region

    field :date, :date
    field :camera_count, :integer
    field :new_camera_count, :integer
    field :camera_density, :float
    field :growth_rate, :float

    timestamps(type: :utc_datetime)
  end

  @required ~w(region_id date camera_count new_camera_count)a
  @optional ~w(camera_density growth_rate)a

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:region_id, :date], error_key: :date)
    |> foreign_key_constraint(:region_id)
  end
end
