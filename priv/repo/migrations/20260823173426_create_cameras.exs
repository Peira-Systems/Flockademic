defmodule Flockademic.Repo.Migrations.CreateCameras do
  use Ecto.Migration

  def change do
    create table(:cameras) do
      add :source, :string, null: false
      add :source_id, :string, null: false
      add :manufacturer, :string
      add :operator, :string
      add :camera_type, :string
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :geom, :"geometry(Point,4326)", null: false

      # `first_observed_at` is the only date the visualization may treat as
      # authoritative history. `installed_at` must stay nil unless a source
      # specifically documents an install/deployment date.
      add :first_observed_at, :utc_datetime, null: false
      add :last_observed_at, :utc_datetime, null: false
      add :installed_at, :utc_datetime
      add :installed_at_source, :string
      add :installed_at_confidence, :string

      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cameras, [:source, :source_id])
    create index(:cameras, [:first_observed_at])

    execute "CREATE INDEX cameras_geom_index ON cameras USING GIST (geom)",
            "DROP INDEX cameras_geom_index"
  end
end
