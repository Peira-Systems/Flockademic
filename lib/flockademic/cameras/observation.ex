defmodule Flockademic.Cameras.Observation do
  @moduledoc """
  An immutable record of a camera appearing in a particular source snapshot.

  Observations are never edited after insertion — only inserted. They are
  the evidence trail behind a camera's `first_observed_at`/`last_observed_at`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "observations" do
    belongs_to :camera, Flockademic.Cameras.Camera

    field :source, :string
    field :source_record_id, :string
    field :observed_at, :utc_datetime
    field :latitude, :float
    field :longitude, :float
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required ~w(camera_id source source_record_id observed_at latitude longitude)a
  @optional ~w(metadata)a

  def changeset(observation, attrs) do
    observation
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint([:source, :source_record_id], error_key: :source_record_id)
    |> foreign_key_constraint(:camera_id)
  end
end
